// Build log tabs. To add a step: write content/NN-name.md and add one line here.
const TABS = [
  { id: "overview", label: "0 Overview", file: "content/00-overview.md" },
  { id: "setup", label: "1 Setup", file: "content/01-setup.md" },
  { id: "data-sources", label: "2 Data sources", file: "content/02-data-sources.md" },
];

const tabList = document.getElementById("tabs");
const content = document.getElementById("content");
const pager = document.getElementById("pager");
const cache = new Map(); // Markdown already downloaded, by file name
let firstRender = true;

if (window.mermaid) {
  const dark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  mermaid.initialize({ startOnLoad: false, theme: dark ? "dark" : "neutral" });
}

// Build the tab bar once
for (const tab of TABS) {
  const link = document.createElement("a");
  link.href = `#${tab.id}`;
  link.id = `tab-${tab.id}`;
  link.textContent = tab.label;
  link.setAttribute("role", "tab");
  tabList.appendChild(link);
}

async function loadMarkdown(file) {
  if (!cache.has(file)) {
    const response = await fetch(file, { cache: "no-cache" });
    if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
    cache.set(file, await response.text());
  }
  return cache.get(file);
}

async function show(id) {
  const index = Math.max(0, TABS.findIndex((t) => t.id === id));
  const tab = TABS[index];

  // Highlight the active tab
  for (const link of tabList.children) {
    const active = link.id === `tab-${tab.id}`;
    link.classList.toggle("active", active);
    link.setAttribute("aria-selected", String(active));
  }

  // Render the Markdown of the tab
  try {
    content.innerHTML = marked.parse(await loadMarkdown(tab.file));
  } catch (error) {
    content.innerHTML = `<p class="error">Could not load <code>${tab.file}</code> (${error.message}).
      When previewing locally, serve the folder: <code>python -m http.server 8000 --directory site</code></p>`;
  }

  // ```mermaid code blocks become diagrams
  const diagrams = content.querySelectorAll("pre > code.language-mermaid");
  for (const code of diagrams) {
    const box = document.createElement("div");
    box.className = "mermaid";
    box.textContent = code.textContent;
    code.parentElement.replaceWith(box);
  }
  if (diagrams.length && window.mermaid) await mermaid.run({ nodes: content.querySelectorAll(".mermaid") });

  // Wide tables scroll sideways on phones instead of breaking the layout
  for (const table of content.querySelectorAll("table")) {
    const wrapper = document.createElement("div");
    wrapper.className = "table-scroll";
    table.replaceWith(wrapper);
    wrapper.appendChild(table);
  }

  // Previous / next links at the bottom
  const prev = TABS[index - 1];
  const next = TABS[index + 1];
  pager.innerHTML =
    (prev ? `<a class="prev" href="#${prev.id}">Previous: ${prev.label}</a>` : "<span></span>") +
    (next ? `<a class="next" href="#${next.id}">Next: ${next.label}</a>` : "");

  document.title = `${tab.label.replace(/^\d+\s/, "")} | WebShop Pro Analytics`;
  if (!firstRender) {
    window.scrollTo({ top: 0 });
    content.focus({ preventScroll: true });
  }
  firstRender = false;
}

window.addEventListener("hashchange", () => show(location.hash.slice(1)));
show(location.hash.slice(1));