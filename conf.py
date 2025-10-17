# Configuration file for the Sphinx documentation builder.
#
# For the full list of built-in configuration values, see the documentation:
# https://www.sphinx-doc.org/en/master/usage/configuration.html

# -- Project information -----------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#project-information

project = 'Revs Tech Notes'
copyright = '2025, Revannaswamy N'
author = 'Revannaswamy N'
release = '1.0'

# -- General configuration ---------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#general-configuration

extensions = ['sphinx_rtd_theme',
              'sphinx_copybutton',
              'sphinx_code_tabs',
              'rst2pdf.pdfbuilder']

templates_path = ['_templates']
exclude_patterns = ['_build', 'Thumbs.db', '.DS_Store']



# -- Options for HTML output -------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#options-for-html-output

html_theme = 'sphinx_rtd_theme'
html_theme_options = {
    'logo_only': False,
    'collapse_navigation': True,
    'sticky_navigation': True,
    'includehidden': True,
    'navigation_depth': 10,
    'titles_only': False
}

latex_engine = 'pdflatex'   # or 'xelatex'/'lualatex' if you need Unicode fonts
latex_documents = [
    ('index', 'MyProject.tex', 'MyProject Documentation',
     'Your Name', 'manual'),
]


html_static_path = ['_static']

def setup(app):
    app.add_css_file('css/custom.css')