# frozen_string_literal: true

require 'yaml'

# The bundled gamebooks: public domain choose-a-path books, one YAML file per book in
# vendor/gamebooks. Everything is read once and kept in memory — the books are part of
# the deploy, so there is nothing to reload and no API to reach.
#
# A book is a hash: id, title, author, year, about, credit, start, and sections. Each
# section carries text (paragraphs separated by blank lines), an optional page image,
# and its choices: entries with a target section under 'to', or none for a line that is
# only a consequence to read ("Out to the left means they give up and go home"). A
# section with no choices at all is one of the book's endings.
class Gamebooks
  DIR = 'vendor/gamebooks'

  class << self
    def all
      @all ||= Dir[Rails.root.join(DIR, '*.yml')].map { |file| YAML.safe_load_file(file) }
                                                 .sort_by { |book| book['order'] }
    end

    def find(id)
      all.find { |book| book['id'] == id }
    end
  end
end
