const AutoScroll = {
  mounted() {
    this._scrollToBottom()
  },

  updated() {
    this._scrollToBottom()
  },

  _scrollToBottom() {
    this.el.scrollTo({
      top: this.el.scrollHeight,
      behavior: "smooth",
    })
  },
}

export default AutoScroll
