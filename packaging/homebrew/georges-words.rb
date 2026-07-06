# Homebrew cask for George's Words (backlog 9.6).
#
# This file is a TEMPLATE. It goes in a tap repo named
# `zabugov/homebrew-georges-words` at Casks/georges-words.rb, after which:
#   brew install --cask zabugov/georges-words/georges-words
#
# On each release, update `version` (the tag) and `sha256`
# (shasum -a 256 GeorgesWords-X.Y.Z.dmg). This can be automated from
# release.yml once the tap repo exists.

cask "georges-words" do
  version "0.3.0-b16" # release tag without the leading v
  sha256 "REPLACE_WITH_DMG_SHA256"

  url "https://github.com/zabugov/georges-words/releases/download/v#{version}/GeorgesWords-#{version.sub(/-b\d+$/, "")}.dmg"
  name "George's Words"
  desc "Private, on-device dictation: hold a key, speak, polished text appears"
  homepage "https://github.com/zabugov/georges-words"

  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"

  auto_updates true # Sparkle handles updates after install

  app "GeorgesWords.app"

  zap trash: [
    "~/Library/Application Support/GeorgesWords",
    "~/Library/Preferences/com.georges.words.plist",
  ]
end
