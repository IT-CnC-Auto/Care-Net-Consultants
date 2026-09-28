// CNC HSF FORGE | BI-EDGE-01 v1.0.0 | Bee-Inspect input validation 26/09/2026
//
// A small validator with the same shape as zod (object, string, int, number,
// boolean, enum, uuid, optional, strict, parse, safeParse), written by hand
// because zod cannot be imported by the Edge Functions (npm: specifier) and by
// node --test from the same file without the network at test time. Plain ES
// module, no dependencies; runs unchanged in Deno and Node 22.
//
//   const Body = v.object({ inspection_id: v.uuid(), use_ai: v.boolean().optional() });
//   const r = Body.safeParse(json);  // { success: true, data } | { success: false, error: { issues } }
//   Body.parse(json);                // returns data or throws ValidationError (.status = 400)
//
// Objects are strict by default: an unknown key is an issue, so a caller can
// never slip an extra field (a tenant, a price, a status) past an endpoint.

export class ValidationError extends Error {
  constructor(issues) {
    super('The request is not valid: ' + issues.map((i) => (i.path.length ? i.path.join('.') + ': ' : '') + i.message).join('; '));
    this.name = 'ValidationError';
    this.status = 400;
    this.issues = issues;
  }
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

class Schema {
  constructor(check) {
    this._check = check;
    this._optional = false;
    this._nullable = false;
  }
  // Modifiers change this schema and return it (schemas are built inline, never shared).
  optional() { this._optional = true; return this; }
  nullable() { this._nullable = true; return this; }
  _run(value, path, issues) {
    if (value === undefined) {
      if (this._optional) return undefined;
      issues.push({ path, message: 'is required' });
      return undefined;
    }
    if (value === null) {
      if (this._nullable) return null;
      issues.push({ path, message: 'must not be null' });
      return undefined;
    }
    return this._check(value, path, issues);
  }
  safeParse(value) {
    const issues = [];
    const data = this._run(value, [], issues);
    return issues.length ? { success: false, error: { issues } } : { success: true, data };
  }
  parse(value) {
    const r = this.safeParse(value);
    if (!r.success) throw new ValidationError(r.error.issues);
    return r.data;
  }
}

class StringSchema extends Schema {
  constructor() {
    super((value, path, issues) => {
      if (typeof value !== 'string') {
        issues.push({ path, message: 'must be text' });
        return undefined;
      }
      if (this._min !== undefined && value.length < this._min) issues.push({ path, message: `must be at least ${this._min} characters` });
      if (this._max !== undefined && value.length > this._max) issues.push({ path, message: `must be at most ${this._max} characters` });
      if (this._re && !this._re.test(value)) issues.push({ path, message: this._reMessage || 'has the wrong shape' });
      return value;
    });
  }
  min(n) { this._min = n; return this; }
  max(n) { this._max = n; return this; }
  regex(re, message) { this._re = re; this._reMessage = message; return this; }
}

class NumberSchema extends Schema {
  constructor(integer) {
    super((value, path, issues) => {
      if (typeof value !== 'number' || !Number.isFinite(value)) {
        issues.push({ path, message: 'must be a number' });
        return undefined;
      }
      if (integer && !Number.isSafeInteger(value)) issues.push({ path, message: 'must be a whole number' });
      if (this._min !== undefined && value < this._min) issues.push({ path, message: `must be at least ${this._min}` });
      if (this._max !== undefined && value > this._max) issues.push({ path, message: `must be at most ${this._max}` });
      return value;
    });
  }
  min(n) { this._min = n; return this; }
  max(n) { this._max = n; return this; }
}

class ObjectSchema extends Schema {
  constructor(shape) {
    super((value, path, issues) => {
      if (typeof value !== 'object' || Array.isArray(value)) {
        issues.push({ path, message: 'must be an object' });
        return undefined;
      }
      const out = {};
      if (!this._passthrough) {
        for (const k of Object.keys(value)) {
          if (!Object.prototype.hasOwnProperty.call(shape, k)) issues.push({ path: path.concat(k), message: 'is not a known field' });
        }
      }
      for (const [k, s] of Object.entries(shape)) {
        const v = s._run(value[k], path.concat(k), issues);
        if (v !== undefined) out[k] = v;
      }
      if (this._passthrough) {
        for (const k of Object.keys(value)) if (!(k in out) && !(k in shape)) out[k] = value[k];
      }
      return out;
    });
    this.shape = shape;
  }
  passthrough() { this._passthrough = true; return this; }
  strict() { this._passthrough = false; return this; }
}

class ArraySchema extends Schema {
  constructor(item) {
    super((value, path, issues) => {
      if (!Array.isArray(value)) {
        issues.push({ path, message: 'must be a list' });
        return undefined;
      }
      if (this._max !== undefined && value.length > this._max) issues.push({ path, message: `must hold at most ${this._max} items` });
      return value.map((x, i) => item._run(x, path.concat(i), issues));
    });
  }
  max(n) { this._max = n; return this; }
}

export const v = {
  string: () => new StringSchema(),
  uuid: () => new StringSchema().regex(UUID_RE, 'must be an id (uuid)'),
  int: () => new NumberSchema(true),
  number: () => new NumberSchema(false),
  boolean: () => new Schema((value, path, issues) => {
    if (typeof value !== 'boolean') { issues.push({ path, message: 'must be true or false' }); return undefined; }
    return value;
  }),
  enum: (values) => new Schema((value, path, issues) => {
    if (!values.includes(value)) { issues.push({ path, message: `must be one of ${values.join(', ')}` }); return undefined; }
    return value;
  }),
  object: (shape) => new ObjectSchema(shape),
  array: (item) => new ArraySchema(item),
  any: () => new Schema((value) => value),
};

// Shapes shared by the Bee-Inspect functions.
export const IDEMPOTENCY_KEY_RE = /^[A-Za-z0-9:._-]{8,200}$/;
export const AD_ID_RE = /^AD-(0[1-9]|10)$/;
export const UTM_RE = /^[A-Za-z0-9._-]{1,64}$/;
export const PAGES = Object.freeze(['/hsf-builder', '/health-and-safety-file', '/portal', '/bee-inspect']);
