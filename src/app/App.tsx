import { TerminalHeader } from "./components/terminal-header";
import { TerminalSection } from "./components/terminal-section";
import { InstallTabs } from "./components/install-tabs";
import { CodeBlock } from "./components/code-block";
import logo from "../imports/logo.svg";

export default function App() {
  return (
    <div className="min-h-screen bg-[#0a0a0a] text-white">
      <TerminalHeader />
      
      <main className="container mx-auto px-4 py-6 max-w-7xl">
        {/* Hero Section */}
        <div className="mb-6 border border-[#444] bg-black p-6 font-mono">
          <div className="flex items-start gap-6">
            <img src={logo} alt="NanoSandbox" className="h-16 w-auto flex-shrink-0 mt-2" />
            <div>
              <h1 className="text-3xl font-bold text-[#ff6b6b] mb-2">
                NANOSANDBOX
              </h1>
              <p className="text-white text-lg mb-2">
                Isolated Code Agent Management CLI
              </p>
              <p className="text-[#888] text-sm leading-relaxed">
                Deploy, manage, and orchestrate code agents in separate sandboxed <br />
                environments within a single project. Built for developers who need <br />
                isolation, reproducibility, and control.
              </p>
            </div>
          </div>
        </div>

        {/* Getting Started */}
        <TerminalSection title="Getting Started" id="getting-started" className="mb-6">
          <div className="space-y-4">
            <div>
              <p className="text-[#888] text-sm mb-3">
                Install NanoSandbox with a single command. Works on Linux, macOS, and Windows (WSL).
              </p>
              <InstallTabs />
            </div>

            <div className="border-t border-[#333] pt-4">
              <p className="text-[#888] text-sm mb-2"># Verify installation</p>
              <CodeBlock code="nanosandbox --version" />
            </div>

            <div className="border-t border-[#333] pt-4">
              <p className="text-[#888] text-sm mb-2"># Quick start</p>
              <CodeBlock code={`nanosandbox init my-project
cd my-project
nanosandbox agent create my-agent
nanosandbox agent start my-agent`} />
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
                  <span className="text-white">Isolated Environments</span>
                  <p className="text-[#888] text-xs">Containerized sandboxes with dedicated resources</p>
                </div>
              </div>
              <div className="flex items-start gap-2">
                <span className="text-[#ff6b6b]">✓</span>
                <div>
                  <span className="text-white">Multi-Agent Projects</span>
                  <p className="text-[#888] text-xs">Manage multiple agents in one project structure</p>
                </div>
              </div>
              <div className="flex items-start gap-2">
                <span className="text-[#ff6b6b]">✓</span>
                <div>
                  <span className="text-white">Zero Configuration</span>
                  <p className="text-[#888] text-xs">Deploy agents instantly with automatic setup</p>
                </div>
              </div>
              <div className="flex items-start gap-2">
                <span className="text-[#ff6b6b]">✓</span>
                <div>
                  <span className="text-white">Inter-Agent Communication</span>
                  <p className="text-[#888] text-xs">Built-in networking for secure agent coordination</p>
                </div>
              </div>
              <div className="flex items-start gap-2">
                <span className="text-[#ff6b6b]">✓</span>
                <div>
                  <span className="text-white">Config as Code</span>
                  <p className="text-[#888] text-xs">YAML/JSON definitions for version control</p>
                </div>
              </div>
              <div className="flex items-start gap-2">
                <span className="text-[#ff6b6b]">✓</span>
                <div>
                  <span className="text-white">Security First</span>
                  <p className="text-[#888] text-xs">Sandboxed execution with secrets management</p>
                </div>
              </div>
              <div className="flex items-start gap-2">
                <span className="text-[#ff6b6b]">✓</span>
                <div>
                  <span className="text-white">Version Control</span>
                  <p className="text-[#888] text-xs">Snapshot states and instant rollbacks</p>
                </div>
              </div>
              <div className="flex items-start gap-2">
                <span className="text-[#ff6b6b]">✓</span>
                <div>
                  <span className="text-white">Auto-Restart Policies</span>
                  <p className="text-[#888] text-xs">Health checks and automatic recovery</p>
                </div>
              </div>
            </div>
          </TerminalSection>

          {/* Common Commands */}
          <TerminalSection title="Common Commands" id="commands">
            <div className="space-y-2 text-sm">
              <div className="flex gap-2 text-xs">
                <span className="text-[#888] w-40">nanosandbox init</span>
                <span className="text-[#888]">Initialize new project</span>
              </div>
              <div className="flex gap-2 text-xs">
                <span className="text-[#888] w-40">nanosandbox agent create</span>
                <span className="text-[#888]">Create new agent</span>
              </div>
              <div className="flex gap-2 text-xs">
                <span className="text-[#888] w-40">nanosandbox agent start</span>
                <span className="text-[#888]">Start agent container</span>
              </div>
              <div className="flex gap-2 text-xs">
                <span className="text-[#888] w-40">nanosandbox agent stop</span>
                <span className="text-[#888]">Stop running agent</span>
              </div>
              <div className="flex gap-2 text-xs">
                <span className="text-[#888] w-40">nanosandbox agent list</span>
                <span className="text-[#888]">List all agents</span>
              </div>
              <div className="flex gap-2 text-xs">
                <span className="text-[#888] w-40">nanosandbox agent logs</span>
                <span className="text-[#888]">View agent logs</span>
              </div>
              <div className="flex gap-2 text-xs">
                <span className="text-[#888] w-40">nanosandbox agent exec</span>
                <span className="text-[#888]">Execute command in agent</span>
              </div>
              <div className="flex gap-2 text-xs">
                <span className="text-[#888] w-40">nanosandbox agent install</span>
                <span className="text-[#888]">Install dependencies</span>
              </div>
              <div className="flex gap-2 text-xs">
                <span className="text-[#888] w-40">nanosandbox agent inspect</span>
                <span className="text-[#888]">View agent details</span>
              </div>
              <div className="flex gap-2 text-xs">
                <span className="text-[#888] w-40">nanosandbox agent restart</span>
                <span className="text-[#888]">Restart agent</span>
              </div>
              <div className="flex gap-2 text-xs">
                <span className="text-[#888] w-40">nanosandbox agent remove</span>
                <span className="text-[#888]">Remove agent</span>
              </div>
            </div>
          </TerminalSection>
        </div>

        {/* Isolation Architecture */}
        <TerminalSection title="Isolation & Architecture" id="isolation" className="mb-6">
          <div className="grid md:grid-cols-2 gap-6 text-sm">
            <div className="space-y-4">
              <div>
                <h3 className="text-[#ff6b6b] mb-2">▸ Process Isolation</h3>
                <p className="text-[#888] text-xs leading-relaxed">
                  Each agent runs in its own isolated process space with dedicated CPU and 
                  memory allocations. Crashes or memory leaks in one agent don't affect others. 
                  System-level separation ensures complete independence.
                </p>
              </div>
              <div>
                <h3 className="text-[#ff6b6b] mb-2">▸ Dependency Management</h3>
                <p className="text-[#888] text-xs leading-relaxed">
                  Agents can use different versions of the same library without conflicts. 
                  Each environment has its own package registry and runtime. Install Python 3.8 
                  for one agent and 3.11 for another without interference.
                </p>
              </div>
            </div>
            <div className="space-y-4">
              <div>
                <h3 className="text-[#ff6b6b] mb-2">▸ Network Segmentation</h3>
                <p className="text-[#888] text-xs leading-relaxed">
                  Virtual networks ensure agents can only communicate through defined interfaces. 
                  External network access can be restricted per agent. Built-in service discovery 
                  and DNS resolution for inter-agent communication.
                </p>
              </div>
              <div>
                <h3 className="text-[#ff6b6b] mb-2">▸ Volume Isolation</h3>
                <p className="text-[#888] text-xs leading-relaxed">
                  File systems are isolated by default. Share specific directories between agents 
                  using explicit volume mounts defined in your config. Prevents unauthorized 
                  file access and data leakage between agents.
                </p>
              </div>
            </div>
          </div>
        </TerminalSection>

        {/* Example Workflow */}
        <TerminalSection title="Example Workflow" id="example" className="mb-6">
          <div className="text-sm">
            <p className="text-[#888] mb-3">
              Create a multi-agent project with data processing and API service agents:
            </p>
            <CodeBlock
              code={`# Initialize project
nanosandbox init analytics-platform && cd analytics-platform

# Create data processor agent (Python)
nanosandbox agent create data-processor --runtime python:3.11
nanosandbox agent install data-processor pandas numpy scikit-learn

# Create API service agent (Node.js)
nanosandbox agent create api-service --runtime node:20
nanosandbox agent install api-service express axios

# Configure inter-agent networking
nanosandbox network create analytics-net
nanosandbox network connect analytics-net data-processor api-service

# Start all agents
nanosandbox agent start data-processor
nanosandbox agent start api-service

# Monitor logs
nanosandbox agent logs data-processor --follow
nanosandbox agent logs api-service --tail 100

# View agent status
nanosandbox agent list --status`}
            />
          </div>
        </TerminalSection>

        {/* Advanced Features */}
        <div className="grid md:grid-cols-3 gap-6 mb-6">
          <TerminalSection title="Snapshots" id="snapshots">
            <div className="text-xs space-y-2">
              <p className="text-[#888]">
                Create point-in-time snapshots of agent states for instant rollback and disaster recovery.
              </p>
              <CodeBlock code={`nanosandbox agent snapshot create my-agent
nanosandbox agent snapshot restore my-agent snap-001`} />
            </div>
          </TerminalSection>

          <TerminalSection title="Health Checks" id="health">
            <div className="text-xs space-y-2">
              <p className="text-[#888]">
                Configure automatic health monitoring with custom scripts and restart policies.
              </p>
              <CodeBlock code={`nanosandbox agent config my-agent --health-check /health --interval 30s`} />
            </div>
          </TerminalSection>

          <TerminalSection title="Interactive Shell" id="shell">
            <div className="text-xs space-y-2">
              <p className="text-[#888]">
                Attach to running agents and execute commands directly in their isolated environment.
              </p>
              <CodeBlock code={`nanosandbox agent exec my-agent --interactive /bin/bash`} />
            </div>
          </TerminalSection>
        </div>

        {/* Footer */}
        <div className="border border-[#444] bg-black p-4 font-mono text-center">
          <div className="flex items-center justify-center gap-8 text-xs text-[#888] mb-2">
            <a href="#" className="hover:text-[#ff6b6b] transition-colors">Documentation</a>
            <a href="#" className="hover:text-[#ff6b6b] transition-colors">GitHub</a>
            <a href="#" className="hover:text-[#ff6b6b] transition-colors">Community</a>
            <a href="#" className="hover:text-[#ff6b6b] transition-colors">License: MIT</a>
          </div>
          <p className="text-[#666] text-xs">
            NanoSandbox © 2026 | Open Source Project
          </p>
        </div>
      </main>

      {/* Bottom Status Bar */}
      <div className="fixed bottom-0 left-0 right-0 border-t border-[#444] bg-black">
        <div className="px-4 py-1 flex items-center gap-4 font-mono text-xs">
          <span className="text-[#ff6b6b]">$</span>
          <span className="text-[#888]">nanosandbox --help</span>
          <div className="flex-1"></div>
          <span className="text-[#888]">[Ctrl+C] Exit</span>
          <span className="text-[#888]">[↑↓] Navigate</span>
          <span className="text-[#888]">[Enter] Select</span>
        </div>
      </div>
    </div>
  );
}