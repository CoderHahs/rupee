import { Controller } from "@hotwired/stimulus";

// Pre-selects the browser's time zone when the family has none yet, so an
// admin confirming the household time zone usually only has to submit.
export default class extends Controller {
  static targets = ["select"];

  connect() {
    if (this.selectTarget.value) return;

    const zone = Intl.DateTimeFormat().resolvedOptions().timeZone;
    const option = Array.from(this.selectTarget.options).find(
      (candidate) => candidate.value === zone,
    );
    if (option) this.selectTarget.value = zone;
  }
}
