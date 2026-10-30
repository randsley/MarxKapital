"""Assembles the GitHub Pages source for MarxKapital (built by Jekyll with
the Just the Docs theme in .github/workflows/pages.yml).

    python .github/pages/build_site.py OUT_DIR

The home pages (home.md, home.pt.md here) are hand-written; the other pages
come from the repository's Markdown (README as the overview, CHANGELOG,
docs/, notebooks/README.md, in English and Portuguese where both exist).
The site also gets the paper PDF, a few paper figures converted to PNG
(pdftoppm), the executed Jupyter notebooks rendered to HTML (nbconvert) and
a thumbnail of each notebook's first plot. Relative links to files on the
site are rewritten to their .html pages; links to other repository files
point to GitHub.
"""

import base64
import html
import json
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
GITHUB = "https://github.com/randsley/MarxKapital/blob/main/"

# source (relative to the repository, or home pages in this folder)
# -> (site path, front matter)
PAGES = {
    "home.md": ("index.md", {"title": "Home", "nav_order": 1}),
    "README.md": ("overview.md", {"title": "Overview", "nav_order": 2}),
    "notebooks/README.md": ("notebooks/index.md", {"title": "Notebooks", "nav_order": 3}),
    "docs/LIMITATIONS.md": ("limitations.md", {"title": "Known limitations", "nav_order": 4}),
    "docs/PROJECT_STATUS.md": ("status.md", {"title": "Project status", "nav_order": 5}),
    "docs/GLOSSARY.md": ("glossary.md", {"title": "Glossary", "nav_order": 6}),
    "CHANGELOG.md": ("changelog.md", {"title": "Changelog", "nav_order": 7}),
    "home.pt.md": ("index.pt.md", {"title": "Português", "nav_order": 9, "has_children": True}),
    "README.pt.md": ("overview.pt.md", {"title": "Visão geral", "parent": "Português", "nav_order": 1}),
    "docs/LIMITATIONS.pt.md": ("limitations.pt.md", {"title": "Limitações conhecidas", "parent": "Português", "nav_order": 2}),
    "docs/PROJECT_STATUS.pt.md": ("status.pt.md", {"title": "Estado do projeto", "parent": "Português", "nav_order": 3}),
    "CHANGELOG.pt.md": ("changelog.pt.md", {"title": "Registo de alterações", "parent": "Português", "nav_order": 4}),
}
HOME_PAGES = {"home.md", "home.pt.md"}
NOTEBOOK_DIR = "notebooks/jupyter"
PAPER = "paper/main.pdf"
FIGURES = ["fig1_time_series", "fig2_matrix_A", "fig3_transformation",
           "fig10b_accumulation_cycles", "fig11b_hopf_boundary"]

ACRONYMS = {"tssi", "ad"}
SELF_LINK = re.compile(r" · \*(?:Website|Site): <https://randsley\.github\.io/[^>]*>\*")

LINK = re.compile(r"(\]\()([^)\s#]+)(#[^)\s]*)?\)")


def site_targets():
    targets = {src: dst for src, (dst, _) in PAGES.items() if src not in HOME_PAGES}
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


def front_matter(fields):
    lines = ["---"]
    for k, v in fields.items():
        lines.append(f"{k}: {json.dumps(v, ensure_ascii=False)}")
    return "\n".join(lines + ["---", ""])


def citation():
    with open(os.path.join(REPO, "CITATION.cff"), encoding="utf-8") as f:
        cff = f.read()
    field = lambda name: re.search(rf"^{name}:\s*\"?([^\"\n]+)\"?", cff, re.M).group(1)
    preferred = cff[cff.index("preferred-citation:"):]
    software = cff[:cff.index("preferred-citation:")]
    families = re.findall(r"family-names:\s*\"([^\"]+)\"", software)
    givens = re.findall(r"given-names:\s*\"([^\"]+)\"", software)
    return {
        "VERSION": field("version"),
        "DOI": field("doi"),
        "TITLE": field("title"),
        "YEAR": field("date-released")[:4],
        "AUTHORS": "; ".join(f"{fam}, {giv}" for fam, giv in zip(families, givens)),
        "PAPER_DOI": re.search(r"doi:\s*(\S+)", preferred).group(1),
    }


def notebooks_table():
    """(name, description) of each Jupyter notebook, from notebooks/README.md."""
    with open(os.path.join(REPO, "notebooks/README.md"), encoding="utf-8") as f:
        rows = re.findall(r"^\| \[(\w+)\]\(jupyter/\1\.ipynb\) \| (.+?) \|$", f.read(), re.M)
    return rows


def write_thumbnails(out):
    """First PNG output of each notebook -> notebooks/thumbs/NAME.png."""
    thumbs = os.path.join(out, "notebooks", "thumbs")
    os.makedirs(thumbs, exist_ok=True)
    for name, _ in notebooks_table():
        with open(os.path.join(REPO, NOTEBOOK_DIR, name + ".ipynb"), encoding="utf-8") as f:
            nb = json.load(f)
        png = next((o["data"]["image/png"] for c in nb["cells"] if c["cell_type"] == "code"
                    for o in c.get("outputs", []) if "image/png" in o.get("data", {})), None)
        if png is not None:
            data = "".join(png) if isinstance(png, list) else png
            with open(os.path.join(thumbs, name + ".png"), "wb") as f:
                f.write(base64.b64decode(data))


def gallery(dst, out):
    cards = []
    for name, description in notebooks_table():
        words = name.split("_")[1:]
        title = " ".join(w.upper() if w in ACRONYMS else w for w in words)
        title = title[0].upper() + title[1:]
        href = relative(dst, f"{NOTEBOOK_DIR}/{name}.html")
        thumb = os.path.join("notebooks", "thumbs", name + ".png")
        img = (f'<img src="{relative(dst, thumb)}" alt="First plot of the {title} notebook">'
               if os.path.exists(os.path.join(out, thumb)) else "")
        cards.append(f'<a href="{href}">{img}<strong>{name[:2]} · {title}</strong>'
                     f"<span>{html.escape(description)}</span></a>")
    return '<div class="nb-grid">\n' + "\n".join(cards) + "\n</div>"


def write_figures(out):
    fig_out = os.path.join(out, "assets", "figures")
    os.makedirs(fig_out, exist_ok=True)
    for name in FIGURES:
        subprocess.run(["pdftoppm", "-png", "-r", "150", "-singlefile",
                        os.path.join(REPO, "paper", "figures", name + ".pdf"),
                        os.path.join(fig_out, name)], check=True)


def main(out):
    if os.path.exists(out):
        shutil.rmtree(out)
    os.makedirs(out)
    targets = site_targets()
    cite = citation()
    write_figures(out)
    write_thumbnails(out)

    for src, (dst, fields) in PAGES.items():
        path_in = os.path.join(HERE if src in HOME_PAGES else REPO, src)
        with open(path_in, encoding="utf-8") as f:
            text = f.read()
        if src in HOME_PAGES:
            for key, value in cite.items():
                text = text.replace(f"@@{key}@@", value)
            text = text.replace("@@GALLERY@@", gallery(dst, out))
        else:
            text = rewrite_links(SELF_LINK.sub("", text), src, dst, targets)
        if src == "notebooks/README.md":
            # gallery right after the introduction, before the tables
            text = text.replace("\n## Jupyter\n", "\n" + gallery(dst, out) + "\n\n## Jupyter\n", 1)
        path = os.path.join(out, dst)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(front_matter(fields) + "\n" + text)

    os.makedirs(os.path.join(out, "paper"), exist_ok=True)
    shutil.copy(os.path.join(REPO, PAPER), os.path.join(out, PAPER))

    nb_out = os.path.join(out, NOTEBOOK_DIR)
    os.makedirs(nb_out, exist_ok=True)
    notebooks = sorted(os.path.join(REPO, NOTEBOOK_DIR, f)
                       for f in os.listdir(os.path.join(REPO, NOTEBOOK_DIR)) if f.endswith(".ipynb"))
    subprocess.run([sys.executable, "-m", "nbconvert", "--to", "html", "--output-dir", nb_out,
                    *notebooks], check=True)

    shutil.copy(os.path.join(HERE, "_config.yml"), out)
    shutil.copytree(os.path.join(HERE, "_includes"), os.path.join(out, "_includes"))


if __name__ == "__main__":
    main(os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "_site_src"))
