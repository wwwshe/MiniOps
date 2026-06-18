# frozen_string_literal: true

class Miniops < Formula
  desc "Headless Mac Mini server monitoring agent"
  homepage "https://github.com/wwwshe/MiniOps"
  license "MIT"
  head "https://github.com/wwwshe/MiniOps.git", branch: "main"

  depends_on :macos

  def install
    odie "Command Line Tools required. Run: xcode-select --install" unless MacOS::CLT.installed? || MacOS::Xcode.installed?

    system "swift", "build",
           "-c", "release",
           "--disable-sandbox",
           "--product", "miniopsd"
    bin.install ".build/release/miniopsd"
  end

  service do
    run [opt_bin/"miniopsd"]
    keep_alive true
    log_path var/"log/miniopsd.log"
    error_log_path var/"log/miniopsd.err.log"
  end

  test do
    assert_match "miniopsd", shell_output("#{bin}/miniopsd --help")
  end
end
