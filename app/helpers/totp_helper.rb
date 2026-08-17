# frozen_string_literal: true

module TotpHelper
  # A stored setup key, rendered in Totp.rows' hand-copying layout: as one multi-line glyph
  # on the phosphor styles, and as text broken across lines everywhere else.
  def setup_key(secret)
    rows = Totp.rows(secret)
    return glyph_image(rows.join("\n")) if glyph_theme

    safe_join(rows, tag.br)
  end
end
