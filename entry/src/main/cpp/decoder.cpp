#include <napi/native_api.h>
#include <native_window/external_window.h>
#include <multimedia/player_framework/native_avcodec_videodecoder.h>
#include <multimedia/player_framework/native_avbuffer.h>
#include <multimedia/player_framework/native_avformat.h>
#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#include <cmath>
#include <cerrno>
#include <cstdlib>

namespace {
constexpr size_t MAX_PACKET = 4 * 1024 * 1024;
constexpr size_t MAX_BYTES = 12 * 1024 * 1024;
constexpr size_t MAX_FRAMES = 8;
struct Packet { std::vector<uint8_t> bytes; int64_t pts; bool key; };
struct Slot { uint32_t index; OH_AVBuffer *buffer; };
struct Status {
    uint32_t epoch = 0; bool ready = false; int32_t width = 0; int32_t height = 0;
    uint32_t rendered = 0; uint32_t dropped = 0; size_t queued = 0; std::string error;
};
class Decoder {
public:
    Decoder() { worker_ = std::thread([this] { Run(); }); }
    ~Decoder() { { std::lock_guard<std::mutex> lock(mutex_); quit_ = true; } cv_.notify_one(); worker_.join(); }
    uint32_t Start(uint64_t surface, int32_t width, int32_t height) {
        std::lock_guard<std::mutex> lock(mutex_);
        const uint32_t epoch = ++epoch_;
        surface_ = surface; width_ = width; height_ = height; command_ = 1;
        frames_.clear(); bytes_ = 0; waitingKey_ = true;
        status_ = {}; status_.epoch = epoch; status_.width = width; status_.height = height;
        cv_.notify_one(); return epoch;
    }
    void Stop(uint32_t expected) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (expected != epoch_) return;
        ++epoch_; command_ = 2; frames_.clear(); bytes_ = 0; status_.ready = false;
        cv_.notify_one();
    }
    int Push(uint32_t epoch, const uint8_t *data, size_t length, int64_t pts, bool key) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (epoch != epoch_ || command_ == 2 || !status_.error.empty()) return 2;
        if (waitingKey_ && !key) { status_.dropped++; return 1; }
        if (frames_.size() >= MAX_FRAMES || bytes_ + length > MAX_BYTES) {
            status_.dropped += static_cast<uint32_t>(frames_.size()) + 1;
            frames_.clear(); bytes_ = 0; waitingKey_ = true;
            return 1;
        }
        if (key) waitingKey_ = false;
        frames_.push_back({std::vector<uint8_t>(data, data + length), pts, key}); bytes_ += length;
        cv_.notify_one(); return 0;
    }
    Status Snapshot() { std::lock_guard<std::mutex> lock(mutex_); Status value = status_; value.queued = frames_.size(); return value; }
private:
    struct Session { Decoder *owner; uint32_t epoch; std::atomic<bool> active{true}; };
    std::mutex mutex_; std::condition_variable cv_; std::thread worker_;
    std::atomic<uint32_t> epoch_{0}; bool quit_ = false; int command_ = 0;
    uint64_t surface_ = 0; int32_t width_ = 0; int32_t height_ = 0;
    std::deque<Packet> frames_; std::deque<Slot> slots_; size_t bytes_ = 0; bool waitingKey_ = true;
    Status status_; OH_AVCodec *codec_ = nullptr; OHNativeWindow *window_ = nullptr;
    std::unique_ptr<Session> session_;
    static void Error(OH_AVCodec *, int32_t code, void *data) {
        auto *s = static_cast<Session *>(data);
        s->owner->Fail(s->epoch, "H.264 decoder error " + std::to_string(code));
    }
    static void Format(OH_AVCodec *, OH_AVFormat *format, void *data) {
        auto *s = static_cast<Session *>(data); if (!s->active) return;
        int32_t width = 0, height = 0;
        OH_AVFormat_GetIntValue(format, OH_MD_KEY_WIDTH, &width);
        OH_AVFormat_GetIntValue(format, OH_MD_KEY_HEIGHT, &height);
        std::lock_guard<std::mutex> lock(s->owner->mutex_);
        if (s->epoch == s->owner->epoch_ && width > 0 && height > 0) {
            s->owner->status_.width = width; s->owner->status_.height = height;
        }
    }
    static void Input(OH_AVCodec *, uint32_t index, OH_AVBuffer *buffer, void *data) {
        auto *s = static_cast<Session *>(data); if (!s->active) return;
        std::lock_guard<std::mutex> lock(s->owner->mutex_);
        if (s->epoch != s->owner->epoch_) return;
        if (s->owner->slots_.size() >= 64) {
            s->owner->status_.error = "Decoder input buffer overflow"; s->owner->command_ = 2;
        } else s->owner->slots_.push_back({index, buffer});
        s->owner->cv_.notify_one();
    }
    static void Output(OH_AVCodec *codec, uint32_t index, OH_AVBuffer *, void *data) {
        auto *s = static_cast<Session *>(data); if (!s->active || s->epoch != s->owner->epoch_) return;
        const auto result = OH_VideoDecoder_RenderOutputBuffer(codec, index);
        if (result != AV_ERR_OK) { s->owner->Fail(s->epoch, "H.264 surface render failed"); return; }
        std::lock_guard<std::mutex> lock(s->owner->mutex_);
        if (s->epoch == s->owner->epoch_) s->owner->status_.rendered++;
    }
    void Fail(uint32_t epoch, const std::string &message) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (epoch != epoch_) return;
        if (status_.error.empty()) status_.error = message;
        status_.ready = false; command_ = 2;
        frames_.clear(); bytes_ = 0; cv_.notify_one();
    }
    void TearDown() {
        if (session_) session_->active = false;
        if (codec_) { OH_VideoDecoder_Stop(codec_); OH_VideoDecoder_Destroy(codec_); codec_ = nullptr; }
        session_.reset();
        if (window_) { OH_NativeWindow_DestroyNativeWindow(window_); window_ = nullptr; }
        std::lock_guard<std::mutex> lock(mutex_); slots_.clear();
    }
    bool Configure(uint32_t epoch, uint64_t surface, int32_t width, int32_t height) {
        if (OH_NativeWindow_CreateNativeWindowFromSurfaceId(surface, &window_) != 0 || !window_) {
            Fail(epoch, "Native surface unavailable"); return false;
        }
        codec_ = OH_VideoDecoder_CreateByMime("video/avc");
        if (!codec_) { Fail(epoch, "H.264 decoder unavailable"); return false; }
        session_ = std::make_unique<Session>(); session_->owner = this; session_->epoch = epoch;
        const OH_AVCodecCallback callbacks = {Error, Format, Input, Output};
        OH_AVFormat *format = OH_AVFormat_Create();
        if (!format) { Fail(epoch, "Decoder format allocation failed"); return false; }
        OH_AVFormat_SetIntValue(format, OH_MD_KEY_WIDTH, width);
        OH_AVFormat_SetIntValue(format, OH_MD_KEY_HEIGHT, height);
        OH_AVFormat_SetIntValue(format, OH_MD_KEY_MAX_INPUT_SIZE, static_cast<int32_t>(MAX_PACKET));
        OH_AVFormat_SetDoubleValue(format, OH_MD_KEY_FRAME_RATE, 60.0);
        const char *stage = "RegisterCallback";
        auto result = OH_VideoDecoder_RegisterCallback(codec_, callbacks, session_.get());
        if (result == AV_ERR_OK) { stage = "Configure"; result = OH_VideoDecoder_Configure(codec_, format); }
        OH_AVFormat_Destroy(format);
        // SetSurface requires the configured state, before Prepare.
        if (result == AV_ERR_OK) { stage = "SetSurface"; result = OH_VideoDecoder_SetSurface(codec_, window_); }
        if (result == AV_ERR_OK) { stage = "Prepare"; result = OH_VideoDecoder_Prepare(codec_); }
        if (result == AV_ERR_OK) { stage = "Start"; result = OH_VideoDecoder_Start(codec_); }
        if (result != AV_ERR_OK) {
            Fail(epoch, std::string("H.264 ") + stage + " failed " + std::to_string(result)); return false;
        }
        std::lock_guard<std::mutex> lock(mutex_);
        if (epoch == epoch_ && command_ != 2) status_.ready = true;
        return true;
    }
    void Run() {
        for (;;) {
            int command = 0; uint32_t epoch = 0; uint64_t surface = 0; int32_t width = 0, height = 0;
            Slot slot{}; Packet packet; bool feed = false;
            {
                std::unique_lock<std::mutex> lock(mutex_);
                cv_.wait(lock, [this] { return quit_ || command_ || (status_.ready && !frames_.empty() && !slots_.empty()); });
                if (quit_) break;
                command = command_; command_ = 0; epoch = epoch_;
                if (command == 1) { surface = surface_; width = width_; height = height_; }
                else if (!command && status_.ready && !slots_.empty() && !frames_.empty()) {
                    slot = slots_.front(); slots_.pop_front(); packet = std::move(frames_.front()); frames_.pop_front();
                    bytes_ -= packet.bytes.size(); feed = true;
                }
            }
            if (command) {
                TearDown();
                if (command == 1 && epoch == epoch_ && !Configure(epoch, surface, width, height)) TearDown();
            } else if (feed && epoch == epoch_ && codec_) {
                auto *target = OH_AVBuffer_GetAddr(slot.buffer);
                const int32_t capacity = OH_AVBuffer_GetCapacity(slot.buffer);
                if (!target || capacity < 0 || static_cast<size_t>(capacity) < packet.bytes.size()) {
                    Fail(epoch, "H.264 access unit exceeds decoder input buffer"); continue;
                }
                std::memcpy(target, packet.bytes.data(), packet.bytes.size());
                OH_AVCodecBufferAttr attr{}; attr.pts = packet.pts; attr.size = static_cast<int32_t>(packet.bytes.size());
                attr.flags = packet.key ? AVCODEC_BUFFER_FLAGS_SYNC_FRAME : AVCODEC_BUFFER_FLAGS_NONE;
                if (OH_AVBuffer_SetBufferAttr(slot.buffer, &attr) != AV_ERR_OK || OH_VideoDecoder_PushInputBuffer(codec_, slot.index) != AV_ERR_OK) {
                    Fail(epoch, "H.264 input submission failed");
                }
            }
        }
        TearDown();
    }
};
Decoder &Instance() { static Decoder decoder; return decoder; }
napi_value Number(napi_env env, double value) { napi_value result; napi_create_double(env, value, &result); return result; }
napi_value Failure(napi_env env, const char *message) { napi_throw_error(env, nullptr, message); return nullptr; }
napi_value Start(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value args[3]; napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char surface[32]{}; size_t length = 0; int32_t width = 0, height = 0;
    if (argc != 3 || napi_get_value_string_utf8(env, args[0], surface, sizeof(surface), &length) != napi_ok ||
        length == 0 || length >= sizeof(surface) - 1 || napi_get_value_int32(env, args[1], &width) != napi_ok ||
        napi_get_value_int32(env, args[2], &height) != napi_ok || width < 1 || height < 1 || width > 4096 || height > 4096 ||
        static_cast<int64_t>(width) * height > 10000000) return Failure(env, "Invalid decoder surface or dimensions");
    for (size_t i = 0; i < length; i++) if (surface[i] < '0' || surface[i] > '9') return Failure(env, "Invalid surface identifier");
    errno = 0; const uint64_t id = std::strtoull(surface, nullptr, 10);
    if (errno || !id) return Failure(env, "Invalid surface identifier");
    return Number(env, Instance().Start(id, width, height));
}
napi_value Push(napi_env env, napi_callback_info info) {
    size_t argc = 4; napi_value args[4]; napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    uint32_t epoch = 0; void *buffer = nullptr; size_t size = 0; double pts = 0; bool key = false;
    if (argc != 4 || napi_get_value_uint32(env, args[0], &epoch) != napi_ok ||
        napi_get_arraybuffer_info(env, args[1], &buffer, &size) != napi_ok || !buffer || size < 4 || size > MAX_PACKET ||
        napi_get_value_double(env, args[2], &pts) != napi_ok || !std::isfinite(pts) || pts < 0 || pts > 9007199254740991.0 ||
        napi_get_value_bool(env, args[3], &key) != napi_ok) return Failure(env, "Invalid H.264 packet");
    return Number(env, Instance().Push(epoch, static_cast<uint8_t *>(buffer), size, static_cast<int64_t>(pts), key));
}
napi_value Stop(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value arg; uint32_t epoch = 0; napi_get_cb_info(env, info, &argc, &arg, nullptr, nullptr);
    if (argc != 1 || napi_get_value_uint32(env, arg, &epoch) != napi_ok) return Failure(env, "Invalid decoder epoch");
    Instance().Stop(epoch); napi_value result; napi_get_undefined(env, &result); return result;
}
napi_value Stats(napi_env env, napi_callback_info) {
    const auto value = Instance().Snapshot(); napi_value result; napi_create_object(env, &result);
    napi_set_named_property(env, result, "epoch", Number(env, value.epoch));
    napi_set_named_property(env, result, "width", Number(env, value.width));
    napi_set_named_property(env, result, "height", Number(env, value.height));
    napi_set_named_property(env, result, "rendered", Number(env, value.rendered));
    napi_set_named_property(env, result, "dropped", Number(env, value.dropped));
    napi_set_named_property(env, result, "queued", Number(env, value.queued));
    napi_value ready, error; napi_get_boolean(env, value.ready, &ready); napi_create_string_utf8(env, value.error.c_str(), value.error.size(), &error);
    napi_set_named_property(env, result, "ready", ready); napi_set_named_property(env, result, "error", error); return result;
}
napi_value Init(napi_env env, napi_value exports) {
    const napi_property_descriptor properties[] = {
        {"start", nullptr, Start, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"push", nullptr, Push, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stop", nullptr, Stop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stats", nullptr, Stats, nullptr, nullptr, nullptr, napi_default, nullptr}};
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties); return exports;
}
napi_module module = {1, 0, nullptr, Init, "t3device", nullptr, {0}};
__attribute__((constructor)) void Register() { napi_module_register(&module); }
} // namespace
