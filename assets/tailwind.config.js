// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin")

module.exports = {
  darkMode: 'class',
  content: [
    "./js/**/*.js",
    "../lib/moth_web.ex",
    "../lib/moth_web/**/*.*ex"
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter', '-apple-system', 'BlinkMacSystemFont', 'sans-serif'],
      },
      colors: {
        surface: 'var(--surface)',
        elevated: 'var(--elevated)',
        accent: 'var(--accent)',
        success: 'var(--success)',
        warning: 'var(--warning)',
        danger: 'var(--danger)',
        'prize-gold': 'var(--prize-gold)',
      },
      backgroundColor: {
        DEFAULT: 'var(--bg)',
      },
      textColor: {
        primary: 'var(--text-primary)',
        secondary: 'var(--text-secondary)',
        muted: 'var(--text-muted)',
      },
      borderColor: {
        DEFAULT: 'var(--border)',
      },
    },
  },
  plugins: [
    require("@tailwindcss/forms"),
    plugin(({addVariant}) => addVariant("phx-no-feedback", [".phx-no-feedback&", ".phx-no-feedback &"])),
    plugin(({addVariant}) => addVariant("phx-click-loading", [".phx-click-loading&", ".phx-click-loading &"])),
    plugin(({addVariant}) => addVariant("phx-submit-loading", [".phx-submit-loading&", ".phx-submit-loading &"])),
    plugin(({addVariant}) => addVariant("phx-change-loading", [".phx-change-loading&", ".phx-change-loading &"])),
    plugin(({addBase, addUtilities}) => {
      addBase({
        "[phx-click]": { cursor: "pointer" },
      })
      addUtilities({
        ".phx-no-feedback.phx-no-feedback": {
          ".phx-no-feedback &": { display: "none" },
        },
      })
    }),
  ]
}
