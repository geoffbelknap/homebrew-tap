# typed: false
# frozen_string_literal: true

class Microagency < Formula
  desc "Governed MCP gateway: cred-blind, off-context tool access for any MCP client"
  homepage "https://github.com/geoffbelknap/microagency"
  url "https://github.com/geoffbelknap/microagency.git",
      revision: "e449601a010de93d7853eb9a12fc55f657d5093b"
  version "0.1.0"

  depends_on "go" => :build
  depends_on xcode: :build if OS.mac?
  depends_on "microagent" # runtime: microVM supervisor + guest binaries (the reduce code path)
  depends_on "openbao"    # at-rest secret store for upstream creds (baomanager finds `bao` on PATH)

  def install
    system "make", "build" # builds the bundled wasm engines (Go wasip1), then the binary
    bin.install "microagency"
  end

  def caveats
    <<~EOS
      Start it:   microagency up      (auto-registers with Claude Code; approve once in the browser)
      Check it:   microagency doctor  (wasm engines + microVM runtime health)
      Console:    http://127.0.0.1:8765/console  (add MCP servers, browse the registry, see impact)

      The MCP gateway + declarative reduce work immediately. The Python `reduce code`
      path uses the microVM runtime from the `microagent` dependency.
    EOS
  end

  test do
    assert_match "wasm engines", shell_output("#{bin}/microagency doctor 2>&1")
  end
end
