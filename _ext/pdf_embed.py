from docutils import nodes
from docutils.parsers.rst import Directive, directives
import re

def convert_to_embed_url(url):
    """Auto-convert Google Drive share URL to embeddable preview URL."""

    # Pattern: https://drive.google.com/file/d/FILE_ID/view...
    drive_pattern = r'https://drive\.google\.com/file/d/([a-zA-Z0-9_-]+)'
    match = re.search(drive_pattern, url)

    if match:
        file_id = match.group(1)
        return f"https://drive.google.com/file/d/{file_id}/preview"

    # If already a /preview URL, return as-is
    if '/preview' in url:
        return url

    # For non-Drive external URLs, use Google Docs Viewer
    return f"https://docs.google.com/viewer?url={url}&embedded=true"


class PdfEmbed(Directive):
    required_arguments = 1
    optional_arguments = 0
    option_spec = {
        'height': directives.unchanged,
        'width': directives.unchanged,
        'title': directives.unchanged,
    }

    def run(self):
        raw_url = self.arguments[0]
        embed_url = convert_to_embed_url(raw_url)   # ← auto-converts Drive URLs
        height = self.options.get('height', '600px')
        width = self.options.get('width', '100%')
        title = self.options.get('title', 'PDF Preview')

        html = f'''
        <div style="width:{width}; margin: 1rem 0;">
          <iframe
            src="{embed_url}"
            width="{width}"
            height="{height}"
            style="border: 1px solid #ccc; border-radius: 4px;"
            title="{title}"
            allow="autoplay">
          </iframe>
        </div>
        '''
        return [nodes.raw('', html, format='html')]


def setup(app):
    app.add_directive('pdf-embed', PdfEmbed)
    return {'version': '0.1', 'parallel_read_safe': True}