/* Local provider boundary. This pilot accepts synthetic markers only. No camera or image inputs. */
window.AttendanceBiometrics = Object.freeze({
  realAvailable: false,
  async enroll(store, employee) {
    await store('write', 'sample/' + employee, {
      employee,
      kind: 'synthetic',
      expires: Date.now() + 86400000
    });
  },
  async remove(store, employee) {
    await store('delete', 'sample/' + employee);
  },
  async enrolled(store, employee) {
    const sample = await store('read', 'sample/' + employee);
    if (!sample) return false;
    if (sample.kind !== 'synthetic' || sample.expires <= Date.now()) {
      await store('delete', 'sample/' + employee);
      return false;
    }
    return true;
  },
  async verify(store, employee, method) {
    if (method === 'supervised') return 'supervised';
    if (method === 'simulation_failed' || !(await this.enrolled(store, employee))) return 'simulation_failed';
    return 'simulation'; // A demonstration always awaits a real authorized human review.
  }
});
