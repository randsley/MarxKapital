"""Assembles the GitHub Pages source for MarxKapital (built by Jekyll in
.github/workflows/pages.yml).

    python .github/pages/build_site.py OUT_DIR

Pages come from the repository's Markdown (README, CHANGELOG, docs/,
notebooks/README.md, in English and Portuguese where both exist), the paper
PDF and the executed Jupyter notebooks (rendered to HTML with nbconvert).
Relative links to files on the site are rewritten to their .html pages;
links to other repository files point to GitHub.
"""

import os
import re
import shutil
import subprocess
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GITHUB = "https://github.com/randsley/MarxKapital/blob/main/"

# repository file -> (site path, title, language)
PAGES = {
    "README.md": ("index.md", "MarxKapital", "en"),
    "README.pt.md": ("index.pt.md", "MarxKapital", "pt"),
    "CHANGELOG.md": ("changelog.md", "Changelog", "en"),
    "CHANGELOG.pt.md": ("changelog.pt.md", "Registo de alterações", "pt"),
    "docs/LIMITATIONS.md": ("limitations.md", "Known limitations", "en"),
    "docs/LIMITATIONS.pt.md": ("limitations.pt.md", "Limitações conhecidas", "pt"),
    "docs/PROJECT_STATUS.md": ("status.md", "Project status", "en"),
    "docs/PROJECT_STATUS.pt.md": ("status.pt.md", "Estado do projeto", "pt"),
    "docs/GLOSSARY.md": ("glossary.md", "Glossary", "en"),
    "notebooks/README.md": ("notebooks/index.md", "Notebooks", "en"),
}
NOTEBOOK_DIR = "notebooks/jupyter"
PAPER = "paper/main.pdf"

NAV = {
    "en": [("Home", "index.md"), ("Limitations", "limitations.md"),
           ("Project status", "status.md"), ("Glossary", "glossary.md"),
           ("Changelog", "changelog.md"), ("Notebooks", "notebooks/index.md"),
           ("Paper (PDF)", PAPER), ("GitHub", None), ("Português", "index.pt.md")],
    "pt": [("Início", "index.pt.md"), ("Limitações", "limitations.pt.md"),
           ("Estado do projeto", "status.pt.md"), ("Glossário (EN)", "glossary.md"),
           ("Alterações", "changelog.pt.md"), ("Notebooks (EN)", "notebooks/index.md"),
           ("Artigo (PDF)", PAPER), ("GitHub", None), ("English", "index.md")],
}

LINK = re.compile(r"(\]\()([^)\s#]+)(#[^)\s]*)?\)")


def site_targets():
    targets = {src: dst for src, (dst, _, _) in PAGES.items()}
    for f in os.listdir(os.path.join(REPO, NOTEBOOK_DIR)):
        if f.endswith(".ipynb"):
            targets[f"{NOTEBOOK_DIR}/{f}"] = f"{NOTEBOOK_DIR}/{f[:-6]}.html"
    targets[PAPER] = PAPER
    return targets


def html_path(site_path):
    return site_path[:-3] + ".html" if site_path.endswith(".md") else site_path


def relative(from_site, to_site):
    return os.path.relpath(html_path(to_site), os.path.dirname(from_site) or ".")


def rewrite_links(text, src, dst, targets):
    def fix(m):
        target, anchor = m.group(2), m.group(3) or ""
        if re.match(r"^[a-z]+:", target):
            return m.group(0)
        repo_path = os.path.normpath(os.path.join(os.path.dirname(src), target))
        if repo_path in targets:
            return f"{m.group(1)}{relative(dst, targets[repo_path])}{anchor})"
        return f"{m.group(1)}{GITHUB}{repo_path}{anchor})"
    return LINK.sub(fix, text)


def nav(lang, dst):
    items = []
    for label, target in NAV[lang]:
        href = "https://github.com/randsley/MarxKapital" if target is None else relative(dst, target)
        items.append(f"[{label}]({href})")
    return " · ".join(items)


def main(out):
    if os.path.exists(out):
        shutil.rmtree(out)
    os.makedirs(out)
    targets = site_targets()

    for src, (dst, title, lang) in PAGES.items():
        with open(os.path.join(REPO, src), encoding="utf-8") as f:
            text = f.read()
        text = rewrite_links(text, src, dst, targets)
        page = (f"---\ntitle: {title}\nlang: {lang}\n---\n\n"
                f"<nav markdown=\"1\">\n{nav(lang, dst)}\n</nav>\n\n{text}")
        path = os.path.join(out, dst)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(page)

    os.makedirs(os.path.join(out, "paper"), exist_ok=True)
    shutil.copy(os.path.join(REPO, PAPER), os.path.join(out, PAPER))

    nb_out = os.path.join(out, NOTEBOOK_DIR)
    os.makedirs(nb_out, exist_ok=True)
    notebooks = sorted(os.path.join(REPO, NOTEBOOK_DIR, f)
                       for f in os.listdir(os.path.join(REPO, NOTEBOOK_DIR)) if f.endswith(".ipynb"))
    subprocess.run([sys.executable, "-m", "nbconvert", "--to", "html", "--output-dir", nb_out,
                    *notebooks], check=True)

    shutil.copy(os.path.join(os.path.dirname(__file__), "_config.yml"), out)


if __name__ == "__main__":
    main(os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "_site_src"))
