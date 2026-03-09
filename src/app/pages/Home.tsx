import { TerminalSection } from "../components/terminal-section";
import { InstallTabs } from "../components/install-tabs";
import { CodeBlock } from "../components/code-block";
import logo from "../../imports/logo.svg";

export default function Home() {
  return (
    <>
      {/* Hero Section */}
      <div className="mb-6 border border-[#444] bg-black p-6 font-mono">
        <div className="flex items-start gap-6">
          <img src={logo} alt="NanoSandbox" className="h-16 w-auto flex-shrink-0 mt-2" />
          <div>
            <h1 className="text-3xl font-bold text-[#ff6b6b] mb-2">
              NANOSANDBOX
            </h1>
            <p className="text-white text-lg mb-2">
              VM-Isolated Sandboxes for AI Code Agents
            </p>
            <p className="text-[#888] text-sm leading-relaxed">
              Deploy AI agents in hardware-isolated microVMs with sub-second boot times. OCI image support, cross-platform (macOS, Linux, Windows), and built-in multi-agent TUI for concurrent development workflows.
            </p>
          </div>
        </div>
      </div>

      {/* Getting Started */}
      <TerminalSection title="Getting Started" id="getting-started" className="mb-6">
        <div className="space-y-4">
          <div>
            <p className="text-[#888] text-sm mb-3">
              Install nanosb with a single command. Works on macOS (Apple Silicon) and Linux.
            </p>
            <InstallTabs />
          </div>

          <div className="border-t border-[#333] pt-4">
            <p className="text-[#888] text-sm mb-2"># Verify installation</p>
            <CodeBlock code="nanosb --version" />
          </div>

          <div className="border-t border-[#333] pt-4">
            <p className="text-[#888] text-sm mb-2"># Quick start</p>
            <CodeBlock code={`nanosb pull python:3.12-slim
nanosb run python:3.12-slim python -c "print('Hello from a microVM')"

# Or launch the interactive TUI
nanosb`} />
          </div>
        </div>
      </TerminalSection>

      {/* Two Column Layout */}
      <div className="grid md:grid-cols-2 gap-6 mb-6">
        {/* Features */}
        <TerminalSection title="Features" id="features">
          <div className="space-y-2 text-sm">
            <div className="flex items-start gap-2">
              <span className="text-[#ff6b6b]">✓</span>
              <div>
                <span className="text-white">VM-Level Isolation</span>
                <p className="text-[#888] text-xs">Each sandbox runs in its own microVM via libkrun with an independent kernel</p>
              </div>
            </div>
            <div className="flex items-start gap-2">
              <span className="text-[#ff6b6b]">✓</span>
              <div>
                <span className="text-white">Sub-Second Boot Times</span>
                <p className="text-[#888] text-xs">Optimized libkrun startup for near-instant sandbox creation</p>
              </div>
            </div>
            <div className="flex items-start gap-2">
              <span className="text-[#ff6b6b]">✓</span>
              <div>
                <span className="text-white">OCI Image Support</span>
                <p className="text-[#888] text-xs">Pull from Docker Hub, GHCR, or any private registry</p>
              </div>
            </div>
            <div className="flex items-start gap-2">
              <span className="text-[#ff6b6b]">✓</span>
              <div>
                <span className="text-white">Multi-Agent TUI</span>
                <p className="text-[#888] text-xs">Run multiple AI agents concurrently in panel-based terminal UI</p>
              </div>
            </div>
            <div className="flex items-start gap-2">
              <span className="text-[#ff6b6b]">✓</span>
              <div>
                <span className="text-white">Project Mounting</span>
                <p className="text-[#888] text-xs">VirtioFS mounts with automatic git integration and branch tracking</p>
              </div>
            </div>
            <div className="flex items-start gap-2">
              <span className="text-[#ff6b6b]">✓</span>
              <div>
                <span className="text-white">MCP Server Support</span>
                <p className="text-[#888] text-xs">Model Context Protocol integration for agent tooling</p>
              </div>
            </div>
            <div className="flex items-start gap-2">
              <span className="text-[#ff6b6b]">✓</span>
              <div>
                <span className="text-white">Cross-Platform</span>
                <p className="text-[#888] text-xs">macOS Apple Silicon (HVF), Linux (KVM), Windows (HCS)</p>
              </div>
            </div>
            <div className="flex items-start gap-2">
              <span className="text-[#ff6b6b]">✓</span>
              <div>
                <span className="text-white">Streaming I/O</span>
                <p className="text-[#888] text-xs">Real-time output streaming with backpressure handling</p>
              </div>
            </div>
          </div>
        </TerminalSection>

        {/* Common Commands */}
        <TerminalSection title="Common Commands" id="commands">
          <div className="space-y-2 text-sm">
            <div className="flex gap-2 text-xs">
              <span className="text-white w-44 flex-shrink-0">nanosb pull &lt;IMAGE&gt;</span>
              <span className="text-[#888]">Pull an OCI image from a registry</span>
            </div>
            <div className="flex gap-2 text-xs">
              <span className="text-white w-44 flex-shrink-0">nanosb run &lt;IMAGE&gt; [CMD]</span>
              <span className="text-[#888]">Run a command in a new sandbox</span>
            </div>
            <div className="flex gap-2 text-xs">
              <span className="text-white w-44 flex-shrink-0">nanosb exec &lt;ID&gt; &lt;CMD&gt;</span>
              <span className="text-[#888]">Execute command in running sandbox</span>
            </div>
            <div className="flex gap-2 text-xs">
              <span className="text-white w-44 flex-shrink-0">nanosb ps</span>
              <span className="text-[#888]">List running sandboxes</span>
            </div>
            <div className="flex gap-2 text-xs">
              <span className="text-white w-44 flex-shrink-0">nanosb stop &lt;SANDBOX&gt;</span>
              <span className="text-[#888]">Stop a running sandbox</span>
            </div>
            <div className="flex gap-2 text-xs">
              <span className="text-white w-44 flex-shrink-0">nanosb rm &lt;SANDBOX&gt;</span>
              <span className="text-[#888]">Remove a sandbox</span>
            </div>
            <div className="flex gap-2 text-xs">
              <span className="text-white w-44 flex-shrink-0">nanosb images</span>
              <span className="text-[#888]">List cached images</span>
            </div>
            <div className="flex gap-2 text-xs">
              <span className="text-white w-44 flex-shrink-0">nanosb doctor</span>
              <span className="text-[#888]">Check runtime prerequisites</span>
            </div>
            <div className="flex gap-2 text-xs">
              <span className="text-white w-44 flex-shrink-0">nanosb cleanup</span>
              <span className="text-[#888]">Clean up stale project clones</span>
            </div>
          </div>
        </TerminalSection>
      </div>

      {/* Isolation Architecture */}
      <TerminalSection title="Isolation & Architecture" id="isolation" className="mb-6">
        <div className="grid md:grid-cols-2 gap-6 text-sm">
          <div className="space-y-4">
            <div>
              <h3 className="text-[#ff6b6b] mb-2">▸ VM-Based Isolation</h3>
              <p className="text-[#888] text-xs leading-relaxed">
                Each sandbox runs in its own microVM with an independent kernel via libkrun direct FFI. Not namespace-based — real hardware-level isolation. Crashes in one sandbox cannot affect others.
              </p>
            </div>
            <div>
              <h3 className="text-[#ff6b6b] mb-2">▸ Hardware Virtualization</h3>
              <p className="text-[#888] text-xs leading-relaxed">
                Platform-native hypervisors: KVM on Linux, Hypervisor.framework (HVF) on macOS Apple Silicon, and HCS with Hyper-V on Windows. No Docker daemon required.
              </p>
            </div>
          </div>
          <div className="space-y-4">
            <div>
              <h3 className="text-[#ff6b6b] mb-2">▸ TSI Networking</h3>
              <p className="text-[#888] text-xs leading-relaxed">
                Transparent Socket Impersonation allows VMs to make outbound connections seamlessly. Guest DNS routed through host. Configurable network scopes: none, group, public, or full access.
              </p>
            </div>
            <div>
              <h3 className="text-[#ff6b6b] mb-2">▸ OCI Image Handling</h3>
              <p className="text-[#888] text-xs leading-relaxed">
                Pure Rust OCI image pulling with layer caching. Platform-aware image selection (linux/amd64, linux/arm64). All layers merged into a single read-only rootfs mounted inside the VM.
              </p>
            </div>
          </div>
        </div>
      </TerminalSection>

      {/* TUI Workflow */}
      <TerminalSection title="TUI Workflow" id="example" className="mb-6">
        <div className="text-sm">
          <p className="text-[#888] mb-3">
            Launch the interactive TUI to manage multiple AI agents in isolated sandboxes:
          </p>
          <CodeBlock
            code={`# Launch the TUI (auto-detects git project)
nanosb

# Add an AI agent with project mounting
/add claude --project /path/to/project --branch feat/my-feature

# Chat with the agent directly in the panel
> Implement the user authentication module

# Manage multiple agents
/add goose --project /path/to/project
/focus 0                    # Switch between panels

# View and sync project changes
/diff                       # Show uncommitted changes
/gitsync on                 # Enable automatic git sync

# Manage MCP servers
/mcp list                   # List configured servers
/mcp add memory npx @anthropic/memory-server

# Monitor sandboxes
/sandboxes                  # Toggle sandbox sidebar

# Cleanup
/kill 0                     # Destroy sandbox and panel`}
          />
        </div>
      </TerminalSection>

      {/* Footer */}
      <div className="border border-[#444] bg-black p-4 font-mono text-center">
        <div className="flex items-center justify-center gap-8 text-xs text-[#888] mb-2">
          <a href="/docs" className="hover:text-[#ff6b6b] transition-colors">Documentation</a>
          <a href="https://github.com/anthropics/nanosandbox" className="hover:text-[#ff6b6b] transition-colors">GitHub</a>
          <a href="/agents" className="hover:text-[#ff6b6b] transition-colors">Agents</a>
          <a href="/mcp" className="hover:text-[#ff6b6b] transition-colors">MCP</a>
        </div>
        <p className="text-[#666] text-xs">
          NanoSandbox © 2026 | Open Source Project
        </p>
      </div>
    </>
  );
}
