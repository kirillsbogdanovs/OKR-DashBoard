import { LightningElement, api } from 'lwc';

export default class KeyResultItem extends LightningElement {
  @api keyResultWrapper;

  // Gets KR for easier template access
  get kr() {
    return this.keyResultWrapper?.keyResult ?? null;
  }

  // Gets targets of KR
  get targets() {
    const t = this.keyResultWrapper?.targets ?? [];
    return t;
  }

  // Check if any target has a value greater than 0
  get hasTargets() {
    const result = this.targets.some(t => (t?.target ?? 0) > 0);
    return result;
  }

  // Add a unique key to each target for template rendering
  get targetsWithKey() {
    return (this.targets || []).map((t, idx) => ({
      ...t,
      _key: `${t.objectType || 'x'}-${idx}`
    }));
  }
}