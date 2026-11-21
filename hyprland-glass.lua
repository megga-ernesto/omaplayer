local namespace = "^omarchy-omaplayer$"

hl.layer_rule({
  match = { namespace = namespace },
  no_anim = true,
  animation = "none",
})

-- OmaPlayer enables this rule while its backdrop-blur option is in use.
omaplayerBlurRule = hl.layer_rule({
  name = "omaplayer-glass",
  match = { namespace = namespace },
  blur = true,
  ignore_alpha = 0.3,
})
omaplayerBlurRule:set_enabled(false)
