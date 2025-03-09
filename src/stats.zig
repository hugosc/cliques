const std = @import("std");
const expect = std.testing.expect;
const assert = std.debug.assert;
const floatEps = std.math.floatEps;
const approxEqAbs = std.math.approxEqAbs;

pub inline fn castToFloat(comptime FType: type, value: anytype) FType {
    std.builtin.Type;
    const target_bits = @typeInfo(FType).float.bits;
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .float => |f| {
            if (f.bits > target_bits) {
                return @floatCast(value);
            } else return value;
        },
        .comptime_float => return @floatCast(value),
        .int, .comptime_int => return @floatFromInt(value),
        else => @compileError("mean not implemented for " ++ @typeName(T)),
    }
}

pub fn mean(comptime FType: type, values: anytype) FType {
    var acc: FType = 0.0;
    const n: FType = @floatFromInt(values.len);
    for (values) |val| {
        const T = comptime @TypeOf(val);
        switch (@typeInfo(T)) {
            .float => |f| {
                if (f.bits > @typeInfo(FType).float.bits) {
                    acc += @as(FType, val);
                } else acc += val;
            },
            .comptime_float => acc += @floatCast(val),
            .int, .comptime_int => acc += @floatFromInt(val),
            else => @compileError("mean not implemented for " ++ @typeName(T)),
        }
    }
    return acc / n;
}

test "mean" {
    const els = [_]f32{ 0, 1, 2, 3 };
    _ = mean(f32, &els);
}
pub fn variance(comptime FType: type, values: anytype) FType {
    var acc: FType = 0.0;
    var acc_squared: FType = 0.0;

    for (values) |val| {
        const cast_val = castToFloat(FType, val);
        acc += cast_val;
        acc_squared += cast_val * cast_val;
    }
    const _mean = acc / values.len;
    return (acc_squared / values.len) - (_mean * _mean);
}

// iterative version:
//fun(p < 1): p is of the form 0.b_{n-1}b_{n-2}..b_0
//  acc = false
//  for d in least sig to most sig
//      if d = true
//          acc = acc | coinFlip
//      else
//          acc = acc & coinFlip
//  return acc
//
//fun(0.5) [0.1]_2 -> (1) acc = coinFlip
//fun(0.25) [0.01]_2 -> (1) acc = coinFlip (2) acc = coinFlip & coinFlip
//fun(0.375) [0.011]_2 -> (1) acc = coinFlip (2) acc = coinFlip | coinFlip (3) acc = coinFlip & (coinFlip | coinFlip)
//fun(0.625) [0.101]_2 -> (1) acc = coinFlip (2) acc = coinFlip & coinFlip (3) acc = coinFlip | (coinFlip & coinFlip)
// float decomposition
pub fn FloatDec(comptime T: type) type {
    return struct {
        sign: u1,
        exponent: CExpInt,
        significand: SigInt,

        const bits: comptime_int = @typeInfo(T).float.bits;
        const exp_bits: comptime_int = std.math.floatExponentBits(T);
        const frac_bits: comptime_int = std.math.floatFractionalBits(T);
        const mant_bits: comptime_int = std.math.floatMantissaBits(T);

        const Int: type = std.meta.Int(.unsigned, bits);
        const ExpInt: type = std.meta.Int(.unsigned, exp_bits);
        const CExpInt: type = std.meta.Int(.signed, exp_bits + 1);
        const FracInt: type = std.meta.Int(.unsigned, frac_bits);
        const SigInt: type = std.meta.Int(.unsigned, frac_bits + 1);
    };
}
//float decomposition
pub fn floatDec(fl: anytype) FloatDec(@TypeOf(fl)) {
    const T = @TypeOf(fl);
    const FT = FloatDec(T);

    const exp_bias: comptime_int = (1 << FT.exp_bits - 1) - 1;
    const v: std.meta.Int(.unsigned, FT.bits) = @bitCast(fl);

    const sign: u1 = @truncate(v >> FT.bits - 1);
    const exponent: FT.ExpInt = @truncate(v >> FT.mant_bits);
    const frac: FT.FracInt = @truncate(v);

    const imp_bool: FT.SigInt = @as(FT.SigInt, @intFromBool(exponent != 0)) << (FT.frac_bits);
    const significand: FT.SigInt = @as(FT.SigInt, frac) + imp_bool;
    const cexp: FT.CExpInt = exponent;
    return FT{ .sign = sign, .exponent = cexp - exp_bias, .significand = significand };
}
/// Generates (supposedly) iid random bernoullis with prob
pub fn randomBitsU64(prob: f32, buf: []u64, rng: anytype) void {
    assert(prob >= 0.0 and prob <= 1.0);

    if (prob == 1.0) {
        @memset(buf, std.math.boolMask(u64, true));
    }
    const frexp = floatDec(prob);
    var bits = frexp.significand;
    var exp = frexp.exponent;
    // has to do shifts in two operations to avoid undefined behaviour
    bits >>= @ctz(bits);
    bits >>= 1;
    for (buf) |*v| {
        v.* = rng.next();
    }
    while (bits > 0) : (bits >>= 1) {
        if (bits % 2 == 1) {
            for (buf) |*v| {
                v.* |= rng.next();
            }
        } else {
            for (buf) |*v| {
                v.* &= rng.next();
            }
        }
    }
    while (exp < -1) : (exp += 1) {
        for (buf) |*v| {
            v.* &= rng.next();
        }
    }
}
fn maskBit(index: usize) usize {
    const ShiftInt = comptime std.math.Log2Int(usize);
    return @as(usize, 1) << @as(ShiftInt, @truncate(index));
}

fn maskIndex(index: usize) usize {
    const ShiftInt = comptime std.math.Log2Int(usize);
    return index >> @bitSizeOf(ShiftInt);
}

pub fn randomBits(prob: f32, masks: [*]usize, bit_length: usize, rng: anytype) void {
    const u64_len = bit_length / 64;
    const buf: []u64 = masks[0..u64_len];
    randomBitsU64(prob, buf, rng);
    if (u64_len * 64 < bit_length) {
        var single_buf: u64 = undefined;
        randomBitsU64(prob, (&single_buf)[0..1], rng);
        for (u64_len * 64..bit_length) |index| {
            const value = single_buf % 2 == 1;
            const bit = maskBit(index);
            const mask_index = maskIndex(index);
            const new_bit = bit & std.math.boolMask(usize, value);
            masks[mask_index] = (masks[mask_index] & ~bit) | new_bit;
            single_buf >>= 1;
        }
    }
}

test "buf mean" {
    const p: f32 = 0.375;
    var rng = std.Random.DefaultPrng.init(42);
    var buf: [1000]u64 = undefined;
    randomBitsU64(p, &buf, &rng);
    var setBits: f32 = 0;
    for (buf) |u| {
        setBits += @floatFromInt(@popCount(u));
    }
    const meanBits = setBits / (buf.len * 64);
    std.debug.print("mean: {}\n", .{meanBits});
}
