import '../css/app.css'
import { createApp } from 'vue'
import { createPinia } from 'pinia'
import { router } from './router'
import { useThemeStore } from './stores/theme'
import App from './App.vue'

const pinia = createPinia()
const app = createApp(App)
app.use(pinia)
app.use(router)

useThemeStore()

app.mount('#app')
