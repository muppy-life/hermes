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
        if (e.target.classList.contains('kanban-card')) {
          draggedCard = e.target
          e.target.style.opacity = '0.5'
          e.dataTransfer.effectAllowed = 'move'
        }
      })

      // Handle drag end
      this.el.addEventListener('dragend', (e) => {
        if (e.target.classList.contains('kanban-card')) {
          e.target.style.opacity = '1'
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

