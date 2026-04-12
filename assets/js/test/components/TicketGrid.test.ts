import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import TicketGrid from '@/components/game/TicketGrid.vue'

const ticket = {
  id: 'test-ticket',
  rows: [[1, null, 20, null, 30, null, 40, null, 90], [5, null, 15, null, 35, null, 50, null, 80], [8, null, 19, null, 38, null, 60, null, 85]],
  numbers: [1, 5, 8, 15, 19, 20, 30, 35, 38, 40, 50, 60, 80, 85, 90]
}

describe('TicketGrid', () => {
  it('renders 15 numbers', () => {
    const wrapper = mount(TicketGrid, { props: { ticket, struck: new Set(), pickedNumbers: [], interactive: true } })
    const cells = wrapper.findAll('[data-number]')
    expect(cells).toHaveLength(15)
  })

  it('emits strike on number click', async () => {
    const wrapper = mount(TicketGrid, { props: { ticket, struck: new Set(), pickedNumbers: [1], interactive: true } })
    await wrapper.find('[data-number="1"]').trigger('click')
    expect(wrapper.emitted('strike')).toBeTruthy()
  })

  it('does not emit strike on already-struck cell', async () => {
    const wrapper = mount(TicketGrid, { props: { ticket, struck: new Set([1]), pickedNumbers: [1], interactive: true } })
    await wrapper.find('[data-number="1"]').trigger('click')
    expect(wrapper.emitted('strike')).toBeFalsy()
  })
})
