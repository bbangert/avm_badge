import Config

# The Share page's two-badge art: :text draws it in the built-in font,
# :image bakes assets/icons/badge_share into the firmware (about 72K).
config :avm_badge, share_art: :text

# The display driver in the base image: :atomgl, or :lvgl for the AtomVM
# fork's lvgl port driver.
config :avm_badge, display: :lvgl
