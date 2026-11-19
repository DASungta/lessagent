cmake_minimum_required(VERSION 3.5.0)
project(t3device LANGUAGES CXX)
add_library(t3device SHARED decoder.cpp)
target_compile_features(t3device PRIVATE cxx_std_17)
target_compile_options(t3device PRIVATE -Wall -Wextra)
target_link_libraries(t3device PUBLIC libace_napi.z.so libnative_media_vdec.so
  libnative_media_core.so libnative_media_codecbase.so libnative_window.so)
