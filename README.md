# browser.nix

最新の Brave / Google Chrome を提供する Nix overlay です。

| パッケージ | aarch64-darwin | x86_64-darwin | x86_64-linux | aarch64-linux |
|---|---|---|---|---|
| `brave` | ✅ | ✅ | ✅ | ✅ |
| `google-chrome` | ✅ | ✅ | ✅ | ―（公式ビルドなし） |

- **macOS**: 公式配布物（dmg / crx3）をそのままパッケージ化するため、コード署名は維持されます。
- **Linux**: nixpkgs の `brave` / `google-chrome` derivation（依存ライブラリの配線済み）を再利用し、
  version と src だけ最新の公式 deb に差し替えます。

## 使い方

### flake input として overlay を使う

```nix
{
  inputs.browser-nix.url = "github:Penpen7/browser.nix";

  # nixpkgs に overlay を適用
  nixpkgs.overlays = [ inputs.browser-nix.overlays.default ];
}
```

overlay を適用すると `pkgs.brave` と `pkgs.google-chrome` が最新版になります
（`google-chrome` は unfree のため `nixpkgs.config.allowUnfree = true` が必要です）。

NixOS / nix-darwin / home-manager では `environment.systemPackages` や `home.packages` に追加してください。
macOS では `$out/Applications/*.app` として配置されるので、Spotlight から起動したい場合は
[mac-app-util](https://github.com/hraban/mac-app-util) などとの併用を推奨します。

### 直接ビルド / 実行

```sh
nix build .#brave
nix build .#google-chrome
nix run .#brave
```

## バージョン更新

```sh
nix run .#update
```

アーカイブのダウンロードは行わず、すべて上流のメタデータからハッシュを取得するため数秒で完了します。

- Brave: GitHub releases の最新タグと、各アセットの `.sha256` サイドカーを取得します。
  - macOS: dmg（darwin 用 zip はトップレベルの署名を欠くため使いません）
  - Linux: deb（nixpkgs の brave と同じアセット）
- Chrome (macOS): Omaha update API（Chrome の自動更新が使う API）から、
  バージョン付きの永続 URL（crx3 更新パッケージ。中身は dmg）と sha256 を取得します。
- Chrome (Linux): 公式 apt リポジトリの `Packages` インデックスから、
  バージョン付き deb の URL と sha256 を取得します。
  Linux と macOS で stable のバージョンがわずかにズレることがあります。

結果は `sources.json` に書き込まれます。URL はバージョンに紐づくため、
新バージョンが出ても既存リビジョンのビルドは壊れません。
過去バージョンに戻したい場合は `sources.json` を古いリビジョンに checkout してください
（各 API から取得できるのは常に最新 stable のみで、任意の過去バージョンは要求できません。
また Chrome の apt pool 上の旧 deb は Google により削除されることがあります）。

### 自動更新（GitHub Actions）

`.github/workflows/update.yml` が毎日 06:30 JST に `nix run .#update` を実行します。
新バージョンが見つかると、Linux / macOS の両方でビルドし、macOS では
`codesign --verify --deep --strict` まで通したうえで、`sources.json` の更新 PR を自動作成します
（変更がなければ何もしません）。`workflow_dispatch` で手動実行も可能です。
