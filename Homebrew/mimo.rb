cask "mimo" do
  version "0.1.0"
  sha256 :no_check

  url "https://github.com/sriinnu/Mimo/releases/download/v#{version}/Mimo-v#{version}.dmg"
  name "Mimo"
  desc "Git identity switcher for macOS — who do you want to be today?"
  homepage "https://github.com/sriinnu/Mimo"

  app "Mimo.app"

  zap trash: [
    "~/Library/Application Support/com.sriinnu.Mimo",
    "~/Library/Preferences/com.sriinnu.Mimo.plist",
    "~/Library/Saved Application State/com.sriinnu.Mimo.savedState",
    "~/.config/mimo",
  ]
end
