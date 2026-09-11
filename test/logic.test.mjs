import test from 'node:test';
import assert from 'node:assert/strict';
import { angleFromVerticalDrag, clampAngle, lidGeometry } from '../logic.mjs';

test('clampAngle constrains and rounds lid angles', () => {
  assert.equal(clampAngle(12), 15);
  assert.equal(clampAngle(122), 120);
  assert.equal(clampAngle(67.6), 68);
  assert.equal(clampAngle('bad'), 110);
});

test('dragging upward opens the lid and dragging downward closes it', () => {
  assert.equal(angleFromVerticalDrag(80, 200, 175), 90);
  assert.equal(angleFromVerticalDrag(80, 200, 225), 70);
  assert.equal(angleFromVerticalDrag(118, 200, 100), 120);
});

test('lid geometry closes toward the viewer with a lighter matching desktop fold', () => {
  assert.deepEqual(lidGeometry(110, 72), { closure: 0, lidFold: 0, desktopFold: -0.828 });
  const closed = lidGeometry(15, 72);
  assert.equal(closed.closure, 1);
  assert.equal(closed.lidFold, -74);
  assert.ok(closed.desktopFold < 0 && closed.desktopFold > -10);
  assert.equal(lidGeometry(120, 72).lidFold, 3.2);
});
