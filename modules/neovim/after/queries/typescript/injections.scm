; extends

(
  (comment) @_comment
  (template_string) @injection.content
  (#match? @_comment "/\\*sql\\*/")
  (#set! injection.language "sql")
  (#set! injection.include-children)
)
