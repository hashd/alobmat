const ThemeToggle = {
  mounted() {
    const saved = localStorage.getItem("moth-theme")
    if (saved === "dark") {
      document.documentElement.classList.add("dark")
    } else if (saved === "light") {
      document.documentElement.classList.remove("dark")
    }

    this.handleEvent("toggle-theme", () => {
      const isDark = document.documentElement.classList.toggle("dark")
      localStorage.setItem("moth-theme", isDark ? "dark" : "light")
    })
  },
}

export default ThemeToggle
