fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios test

```sh
[bundle exec] fastlane ios test
```

GameKit の全テストを実行

### ios beta

```sh
[bundle exec] fastlane ios beta
```

TestFlight へアップロード（ビルド番号は project.yml の CURRENT_PROJECT_VERSION を使用）

### ios signing_check

```sh
[bundle exec] fastlane ios signing_check
```

API キーだけで Distribution 証明書を読み取る（取得のみ。作成も失効もしない）（#1041）

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
