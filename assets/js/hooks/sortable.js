// Sortable hook — wraps SortableJS and pushes "reorder" with the new id order.
import Sortable from "sortablejs"

const SortableHook = {
  mounted() {
    this.sortable = new Sortable(this.el, {
      animation: 150,
      ghostClass: "opacity-40",
      onEnd: () => {
        const ids = Array.from(this.el.children)
          .map((el) => el.dataset.id)
          .filter(Boolean)
        this.pushEvent("reorder", { ids })
      },
    })
  },
  destroyed() {
    this.sortable && this.sortable.destroy()
  },
}

export default SortableHook
