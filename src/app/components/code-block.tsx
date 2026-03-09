import { Copy, Check } from "lucide-react";
import { useState } from "react";

interface CodeBlockProps {
  code: string;
  language?: string;
}

export function CodeBlock({ code, language = "bash" }: CodeBlockProps) {
  const [copied, setCopied] = useState(false);

  const handleCopy = () => {
    navigator.clipboard.writeText(code);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="relative group border border-[#333] bg-[#000]">
      <div className="absolute top-2 right-2 z-10">
        <button
          onClick={handleCopy}
          className="px-2 py-1 bg-[#111] border border-[#444] text-[#888] hover:text-[#ff6b6b] transition-colors text-xs font-mono"
          aria-label="Copy code"
        >
          {copied ? "[✓ copied]" : "[copy]"}
        </button>
      </div>
      <pre className="p-3 overflow-x-auto">
        <code className="text-sm font-mono text-white">{code}</code>
      </pre>
    </div>
  );
}