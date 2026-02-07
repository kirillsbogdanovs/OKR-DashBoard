import { LightningElement, api } from 'lwc';

export default class KeyResultItem extends LightningElement {
  @api keyResultWrapper;

  get kr() {
    return this.keyResultWrapper?.keyResult ?? null;
  }

  get targets() {
    // support BOTH possible shapes
    return (
      this.keyResultWrapper?.targets ??
      this.keyResultWrapper?.keyResult?.targets ??
      []
    );
  }

  get hasTargets() {
    return this.targets.some(t => (t?.target ?? 0) > 0);
  }
}