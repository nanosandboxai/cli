import { createRoot } from "react-dom/client";
import { BrowserRouter, Routes, Route } from "react-router";
import Layout from "./app/Layout";
import Home from "./app/pages/Home";
import McpPage from "./app/pages/McpPage";
import SkillPage from "./app/pages/SkillPage";
import AgentsPage from "./app/pages/AgentsPage";
import DocsPage from "./app/pages/DocsPage";
import "./styles/index.css";

createRoot(document.getElementById("root")!).render(
  <BrowserRouter>
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<Home />} />
        <Route path="mcp" element={<McpPage />} />
        <Route path="skill" element={<SkillPage />} />
        <Route path="agents" element={<AgentsPage />} />
        <Route path="docs" element={<DocsPage />} />
      </Route>
    </Routes>
  </BrowserRouter>
);
