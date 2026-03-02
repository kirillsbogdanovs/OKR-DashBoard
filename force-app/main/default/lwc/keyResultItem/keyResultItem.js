import { LightningElement, api } from 'lwc';

export default class KeyResultItem extends LightningElement {
  @api keyResultWrapper;

  get kr() {
    return this.keyResultWrapper?.keyResult ?? null;
  }

  get targets() {
    const t = this.keyResultWrapper?.targets ?? [];
    return t;
  }

  get hasTargets() {
    const result = this.targets.some(t => (t?.target ?? 0) > 0);
    return result;
  }

  get targetsWithKey() {
    return (this.targets || []).map((t, idx) => ({
      ...t,
      _key: `${t.objectType || 'x'}-${idx}`
    }));
  }
}