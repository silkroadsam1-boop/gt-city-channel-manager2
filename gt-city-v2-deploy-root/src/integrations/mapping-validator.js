'use strict';

/** Validate a channel listing mapping before it is saved.
 * Expected shape: { mappingMode, propertyId, unitId?, roomTypeId?, propertyInventory? }
 * This helper is pure and does not replace database foreign-key/authorization checks.
 */
function validateMapping(input) {
  const errors = [];
  if (!input || typeof input !== 'object') return { valid: false, errors: ['Mapping ma’lumoti noto‘g‘ri.'] };
  const mode = String(input.mappingMode || input.mapping_mode || '').toUpperCase();
  if (!input.propertyId && !input.property_id) errors.push('Property tanlanishi shart.');
  if (!['UNIT', 'ROOM_TYPE', 'PROPERTY'].includes(mode)) errors.push('Mapping turi UNIT, ROOM_TYPE yoki PROPERTY bo‘lishi kerak.');

  const unitId = input.unitId ?? input.unit_id ?? null;
  const roomTypeId = input.roomTypeId ?? input.room_type_id ?? null;
  const propertyInventory = Boolean(input.propertyInventory ?? input.property_inventory ?? false);

  if (mode === 'UNIT' && (!unitId || roomTypeId || propertyInventory)) {
    errors.push('UNIT mapping uchun faqat bitta unit tanlanishi kerak.');
  }
  if (mode === 'ROOM_TYPE' && (!roomTypeId || unitId || propertyInventory)) {
    errors.push('ROOM_TYPE mapping uchun faqat bitta room type tanlanishi kerak.');
  }
  if (mode === 'PROPERTY' && (unitId || roomTypeId || !propertyInventory)) {
    errors.push('PROPERTY mapping butun obyekt inventarini boshqarishi kerak.');
  }
  return { valid: errors.length === 0, errors };
}

module.exports = { validateMapping };
