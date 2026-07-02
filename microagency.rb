# typed: false
# frozen_string_literal: true

class Microagency < Formula
  desc "Governed MCP gateway: cred-blind, off-context tool access for any MCP client"
  homepage "https://github.com/geoffbelknap/microagency"
  url "https://github.com/geoffbelknap/microagency.git",
      revision: "87f2a1bf860daf0f418bcae8353a3104fa6dacd3"
  version "0.1.1"

  depends_on "go" => :build
  depends_on xcode: :build if OS.mac?
  depends_on "microagent" # runtime: microVM supervisor + guest binaries (the reduce code path)
  depends_on "openbao"    # at-rest secret store for upstream creds (baomanager finds `bao` on PATH)

  def install
    system "make", "build" # builds the bundled wasm engines (Go wasip1), then the binary
    bin.install "microagency"
  end

  def caveats
    "Get started:  microagency up"
  end

  test do
    assert_match "wasm engines", shell_output("#{bin}/microagency doctor 2>&1")
  end
end
