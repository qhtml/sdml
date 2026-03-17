'use strict';

const path = require('node:path');
const { Worker } = require('node:worker_threads');

class WorkerPool {
  constructor(size) {
    this.size = Math.max(1, size || 1);
    this.workers = [];
    this.pending = new Map();
    this.roundRobin = 0;
    this.msgId = 1;

    const workerFile = path.join(__dirname, 'request-worker.js');
    for (let i = 0; i < this.size; i += 1) {
      const worker = new Worker(workerFile);
      worker.on('message', (msg) => {
        const pending = this.pending.get(msg.id);
        if (!pending) {
          return;
        }
        this.pending.delete(msg.id);
        if (msg.ok) {
          pending.resolve(msg.result);
        } else {
          pending.reject(new Error(msg.error && msg.error.message ? msg.error.message : 'worker execution failed'));
        }
      });
      worker.on('error', (err) => {
        for (const [id, pending] of this.pending.entries()) {
          if (pending.worker === worker) {
            this.pending.delete(id);
            pending.reject(err);
          }
        }
      });
      this.workers.push(worker);
    }
  }

  execute(payload) {
    if (this.workers.length === 0) {
      return Promise.reject(new Error('worker pool is not initialized'));
    }
    const id = this.msgId;
    this.msgId += 1;
    const worker = this.workers[this.roundRobin % this.workers.length];
    this.roundRobin += 1;

    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject, worker });
      worker.postMessage({ id, payload });
    });
  }

  async close() {
    const workers = [...this.workers];
    this.workers = [];
    await Promise.all(workers.map((worker) => worker.terminate()));
    for (const [, pending] of this.pending.entries()) {
      pending.reject(new Error('worker pool closed before task completion'));
    }
    this.pending.clear();
  }
}

module.exports = {
  WorkerPool,
};
