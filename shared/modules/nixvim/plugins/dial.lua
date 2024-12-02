local augend = require("dial.augend")

require("dial.config").augends:register_group {
  default = {
    augend.constant.alias.bool,
    augend.semver.alias.semver,
    augend.integer.alias.decimal,
    augend.integer.alias.hex,
  },
}
