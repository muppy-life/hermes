// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/hermes"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const Hooks = {
  ActiveNav: {
    mounted() {
      this.highlight(false)
      this._onResize = () => this.highlight(false)
      window.addEventListener("resize", this._onResize)
      // The nav lives in the layout and is not patched on live navigation,
      // so updated() won't fire. Re-highlight whenever a live nav completes.
      this._onNav = () => this.highlight(true)
      window.addEventListener("phx:navigate", this._onNav)
    },
    updated() { this.highlight(true) },
    destroyed() {
      window.removeEventListener("resize", this._onResize)
      window.removeEventListener("phx:navigate", this._onNav)
    },
    highlight(animate) {
      const path = window.location.pathname
      const indicator = this.el.querySelector("#nav-indicator")
      let activeTab = null
      this.el.querySelectorAll(".nav-tab").forEach((tab) => {
        const base = tab.dataset.path
        const active = base === "/dashboard"
          ? path === "/" || path.startsWith("/dashboard")
          : path === base || path.startsWith(base + "/")
        if (active) activeTab = tab
        // Active tab shows white text (over the slate indicator); inactive
        // tabs are muted and get the hover recolor.
        tab.classList.toggle("text-primary-content", active)
        tab.classList.toggle("font-semibold", active)
        tab.classList.toggle("text-base-content/70", !active)
        tab.classList.toggle("hover:text-base-content", !active)
        tab.classList.add("relative", "z-10")
      })
      if (!indicator || !activeTab) return
      // Skip the slide transition on first paint / resize, animate on nav.
      indicator.style.transition = animate ? "" : "none"
      indicator.style.left = activeTab.offsetLeft + "px"
      indicator.style.width = activeTab.offsetWidth + "px"
      indicator.style.opacity = "1"
      if (!animate) {
        // Re-enable transitions after the initial positioning paint.
        indicator.offsetWidth
        indicator.style.transition = ""
      }
    }
  },
  SubtaskInput: {
    mounted() {
      this.handleEvent('clear_subtask_input', () => {
        const input = this.el.querySelector('input[name="title"]')
        if (input) input.value = ''
      })
    }
  },
  ScrollToTop: {
    mounted() { this.step = this.el.dataset.step },
    updated() {
      if (this.el.dataset.step !== this.step) {
        this.step = this.el.dataset.step
        window.scrollTo(0, 0)
      }
    }
  },
  ScrollIndicator: {
    mounted() {
      this.updateIndicators = () => {
        const topIndicator = this.el.querySelector('.scroll-indicator-top')
        const bottomIndicator = this.el.querySelector('.scroll-indicator-bottom')
        const scrollContent = this.el.querySelector('.scroll-content')

        if (topIndicator && bottomIndicator && scrollContent) {
          const isAtTop = scrollContent.scrollTop <= 5
          const isAtBottom = scrollContent.scrollTop + scrollContent.clientHeight >= scrollContent.scrollHeight - 5

          // Show top indicator only if not at top and there's content above
          topIndicator.style.display = isAtTop ? 'none' : 'flex'

          // Show bottom indicator only if not at bottom and there's content below
          bottomIndicator.style.display = isAtBottom ? 'none' : 'flex'
        }
      }

      const scrollContent = this.el.querySelector('.scroll-content')
      if (scrollContent) {
        scrollContent.addEventListener('scroll', this.updateIndicators)

        // Observe content changes (for tab switching)
        this.observer = new MutationObserver(() => {
          setTimeout(() => this.updateIndicators(), 50)
        })

        this.observer.observe(scrollContent, {
          childList: true,
          subtree: true,
          characterData: true
        })

        // Initial check
        setTimeout(() => this.updateIndicators(), 100)
      }
    },

    updated() {
      // Re-check indicators when the component updates (e.g., tab changes)
      setTimeout(() => this.updateIndicators(), 50)
    },

    destroyed() {
      const scrollContent = this.el.querySelector('.scroll-content')
      if (scrollContent) {
        scrollContent.removeEventListener('scroll', this.updateIndicators)
      }
      if (this.observer) {
        this.observer.disconnect()
      }
    }
  },
  KanbanScroll: {
    mounted() {
      this.updateIndicators = () => {
        const leftIndicator = document.getElementById('scroll-indicator-left')
        const rightIndicator = document.getElementById('scroll-indicator-right')

        if (leftIndicator && rightIndicator) {
          const isAtStart = this.el.scrollLeft <= 5
          const isAtEnd = this.el.scrollLeft + this.el.clientWidth >= this.el.scrollWidth - 5

          leftIndicator.style.opacity = isAtStart ? '0' : '1'
          rightIndicator.style.opacity = isAtEnd ? '0' : '1'
        }
      }

      this.el.addEventListener('scroll', this.updateIndicators)

      // Set initial scroll position to show previews of both "New" and "Completed" columns
      // This creates visual hints that users can scroll in both directions
      const newColumn = this.el.querySelector('[data-column-status="new"]')
      const completedColumn = this.el.querySelector('[data-column-status="completed"]')

      if (newColumn && completedColumn) {
        const previewWidth = 60 // Amount to show as preview on each side

        // Calculate the ideal scroll position:
        // Show preview of New column on left, and ensure Completed column preview on right
        const containerWidth = this.el.clientWidth
        const totalScrollWidth = this.el.scrollWidth

        // Position to show New preview on left
        const scrollPosition = newColumn.offsetWidth - previewWidth + 32 // 32px for gap and margin

        // Check if this position would also show the Completed column preview
        const maxScroll = totalScrollWidth - containerWidth
        const finalScrollPosition = Math.min(scrollPosition, maxScroll - previewWidth)

        this.el.scrollLeft = finalScrollPosition
      }

      // Initial check for indicators after setting scroll position
      this.updateIndicators()

      // Drag and drop functionality
      let draggedCard = null

      // Handle drag start
      this.el.addEventListener('dragstart', (e) => {
        const card = e.target.closest('.kanban-card')
        if (card) {
          draggedCard = card
          card.style.opacity = '0.5'
          e.dataTransfer.effectAllowed = 'move'
        }
      })

      // Handle drag end
      this.el.addEventListener('dragend', (e) => {
        const card = e.target.closest('.kanban-card')
        if (card && card === draggedCard) {
          card.style.opacity = '1'
          draggedCard = null
        }
      })

      // Handle drag over (allow drop)
      this.el.addEventListener('dragover', (e) => {
        e.preventDefault()
        const column = e.target.closest('.kanban-cards')
        if (column) {
          e.dataTransfer.dropEffect = 'move'
        }
      })

      // Handle drop
      this.el.addEventListener('drop', (e) => {
        e.preventDefault()

        const targetColumn = e.target.closest('.kanban-cards')
        if (targetColumn && draggedCard) {
          const requestId = draggedCard.dataset.requestId
          const targetColumnId = targetColumn.dataset.columnId
          const targetStatus = targetColumn.dataset.columnStatus

          // Send update to server
          this.pushEvent('move_card', {
            card_id: requestId,
            column_id: targetColumnId,
            position: 0,
            new_status: targetStatus
          })
        }
      })
    }
  },
  MentionInput: {
    mounted() {
      this.users = JSON.parse(this.el.dataset.users || '[]')
      this.textarea = this.el.querySelector('textarea')
      this.dropdown = this.el.querySelector('#mention-dropdown')
      this.mentionStart = -1

      this.textarea.addEventListener('input', (e) => this.handleInput(e))
      this.textarea.addEventListener('keydown', (e) => this.handleKeydown(e))
      this.textarea.addEventListener('blur', () => this.hideDropdown())
      this.handleEvent('clear_comment_input', () => {
        this.textarea.value = ''
        this.hideDropdown()
      })

      // Single delegated listener — survives innerHTML rebuilds
      this.dropdown.addEventListener('mousedown', (e) => {
        // Prevent blur on textarea so the selection can complete
        e.preventDefault()
        const item = e.target.closest('li[data-username]')
        if (item) this.insertMention(item.dataset.username)
      })
    },

    updated() {
      this.users = JSON.parse(this.el.dataset.users || '[]')
    },

    handleInput(e) {
      const text = this.textarea.value
      const cursor = this.textarea.selectionStart
      const textBeforeCursor = text.slice(0, cursor)
      const match = textBeforeCursor.match(/(^|[\s\n])@([\w.+-]*)$/)

      if (match) {
        this.mentionStart = textBeforeCursor.lastIndexOf('@')
        this.showDropdown(match[2].toLowerCase())
      } else {
        this.mentionStart = -1
        this.hideDropdown()
      }
    },

    handleKeydown(e) {
      if (this.dropdown.classList.contains('hidden')) return

      const items = this.dropdown.querySelectorAll('li')
      const active = this.dropdown.querySelector('li.bg-base-300')
      const activeIndex = active ? Array.from(items).indexOf(active) : -1

      if (e.key === 'ArrowDown') {
        e.preventDefault()
        const next = items[activeIndex + 1] || items[0]
        active && active.classList.remove('bg-base-300')
        next && next.classList.add('bg-base-300')
      } else if (e.key === 'ArrowUp') {
        e.preventDefault()
        const prev = items[activeIndex - 1] || items[items.length - 1]
        active && active.classList.remove('bg-base-300')
        prev && prev.classList.add('bg-base-300')
      } else if (e.key === 'Enter' || e.key === 'Tab') {
        const highlighted = this.dropdown.querySelector('li.bg-base-300') || items[0]
        if (highlighted) {
          e.preventDefault()
          this.insertMention(highlighted.dataset.username)
        }
      } else if (e.key === 'Escape') {
        this.hideDropdown()
      }
    },

    showDropdown(query) {
      const matches = this.users.filter(u =>
        u.username.toLowerCase().startsWith(query)
      ).slice(0, 8)

      if (matches.length === 0) {
        this.hideDropdown()
        return
      }

      this.dropdown.innerHTML = ''

      matches.forEach((u, i) => {
        const item = document.createElement('li')
        item.dataset.username = u.username
        item.className = `px-3 py-1.5 text-xs cursor-pointer hover:bg-base-300 flex items-center gap-2 ${i === 0 ? 'bg-base-300' : ''}`

        const usernameSpan = document.createElement('span')
        usernameSpan.className = 'font-semibold'
        usernameSpan.textContent = `@${u.username}`

        item.appendChild(usernameSpan)
        this.dropdown.appendChild(item)
      })

      this.dropdown.classList.remove('hidden')
    },

    hideDropdown() {
      this.dropdown.classList.add('hidden')
      this.dropdown.innerHTML = ''
    },

    insertMention(username) {
      if (this.mentionStart < 0) return
      const before = this.textarea.value.slice(0, this.mentionStart)
      const after = this.textarea.value.slice(this.textarea.selectionStart)
      const newText = `${before}@${username} ${after}`

      this.textarea.value = newText

      const newCursor = this.mentionStart + username.length + 2
      this.textarea.setSelectionRange(newCursor, newCursor)
      this.textarea.focus()

      this.hideDropdown()
      this.mentionStart = -1
    }
  },
  MermaidDiagram: {
    mounted() {
      this.renderDiagram()
    },
    updated() {
      this.renderDiagram()
    },
    renderDiagram() {
      // Use dynamic import to load mermaid
      import('https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs').then(module => {
        const mermaid = module.default
        mermaid.initialize({ startOnLoad: false, theme: 'default' })

        // Find all mermaid elements and render them
        const elements = this.el.querySelectorAll('.mermaid')
        elements.forEach((element, index) => {
          const id = `mermaid-${Date.now()}-${index}`
          mermaid.render(id, element.textContent).then(({ svg }) => {
            element.innerHTML = svg
          }).catch(error => {
            console.error('Mermaid rendering error:', error)
          })
        })
      })
    }
  }
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Go back using real browser history (used by the detail overlay so it
// respects actual navigation instead of pushing a new history entry).
window.addEventListener("phx:history-back", () => history.back())

// Toast stack — append a styled toast (info | success | error | warning)
const TOAST_ICONS = {
  info: '<path stroke-linecap="round" stroke-linejoin="round" d="m11.25 11.25.041-.02a.75.75 0 0 1 1.063.852l-.708 2.836a.75.75 0 0 0 1.063.853l.041-.021M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9-3.75h.008v.008H12V8.25Z"/>',
  success: '<path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"/>',
  error: '<path stroke-linecap="round" stroke-linejoin="round" d="m9.75 9.75 4.5 4.5m0-4.5-4.5 4.5M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"/>',
  warning: '<path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z"/>'
}

function showAppToast(message, type = "info") {
  const c = document.getElementById("toast-c")
  if (!c || !message) return
  const el = document.createElement("div")
  el.className = "app-toast" + (type !== "info" ? " " + type : "")
  el.setAttribute("role", "alert")
  const icon = TOAST_ICONS[type] || TOAST_ICONS.info
  el.innerHTML =
    '<svg class="app-toast-icon" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">' +
    icon + "</svg><span></span>"
  el.querySelector("span").textContent = message
  c.appendChild(el)
  setTimeout(() => {
    el.style.opacity = "0"
    el.style.transform = "translateY(8px)"
    setTimeout(() => el.remove(), 200)
  }, 3500)
}

window.addEventListener("phx:app-toast", (e) => {
  showAppToast(e.detail?.message, e.detail?.type || "info")
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

