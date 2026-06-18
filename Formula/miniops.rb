# frozen_string_literal: true

class Miniops < Formula
  desc "Headless Mac Mini server monitoring agent"
  homepage "https://github.com/wwwshe/MiniOps"
  version "1.0.0"
  license "MIT"

  url "https://github.com/wwwshe/MiniOps/archive/refs/tags/1.0.0.tar.gz"
  sha256 "0c203142e299c9089488ddee9aef2b37247fa721f186aebf622ec450c8e86847"

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
