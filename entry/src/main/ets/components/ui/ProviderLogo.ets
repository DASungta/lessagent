import { ProviderLogoKind, providerLogoKind } from '../../protocol/ThreadRow';

@Component
export struct ProviderLogo {
  @Prop driver: string = '';
  @Prop model: string = '';
  @Prop logoSize: number = 16;

  private kind(): ProviderLogoKind {
    return providerLogoKind(this.driver, this.model);
  }

  private iconResource(kind: ProviderLogoKind): Resource {
    if (kind === 'antigravity') return $r('app.media.provider_antigravity');
    if (kind === 'claude') return $r('app.media.provider_claude');
    if (kind === 'openai') return $r('app.media.provider_openai');
    if (kind === 'cursor') return $r('app.media.provider_cursor');
    if (kind === 'grok') return $r('app.media.provider_grok');
    if (kind === 'opencode') return $r('app.media.provider_opencode');
    if (kind === 'kiro') return $r('app.media.provider_kiro');
    if (kind === 'muse') return $r('app.media.provider_muse');
    if (kind === 'pi') return $r('app.media.provider_pi');
    if (kind === 'fx') return $r('app.media.provider_fx');
    if (kind === 'openrouter') return $r('app.media.provider_openrouter');
    if (kind === 'acp') return $r('app.media.provider_acp');
    if (kind === 'gemini') return $r('app.media.provider_gemini');
    return $r('app.media.provider_generic');
  }

  build() {
    if (this.kind() !== 'none') {
      Image(this.iconResource(this.kind()))
        .width(this.logoSize)
        .height(this.logoSize)
        .objectFit(ImageFit.Contain)
        .accessibilityLevel('no')
    }
  }
}
