// The small mat4 op set the entity animator uses (deterministic op set).
// Projections and the frustum live in PebbleCore (MathX.swift).

import simd

// in-place style mat ops matching the frozen baseline (translate/rotate/scale multiply on the right)
@inline(__always) func mTranslate(_ m: simd_float4x4, _ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    var t = matrix_identity_float4x4
    t.columns.3 = SIMD4<Float>(x, y, z, 1)
    return m * t
}
@inline(__always) func mRotateX(_ m: simd_float4x4, _ a: Float) -> simd_float4x4 {
    let c = cos(a), s = sin(a)
    var r = matrix_identity_float4x4
    r.columns.1 = SIMD4<Float>(0, c, s, 0)
    r.columns.2 = SIMD4<Float>(0, -s, c, 0)
    return m * r
}
@inline(__always) func mRotateY(_ m: simd_float4x4, _ a: Float) -> simd_float4x4 {
    let c = cos(a), s = sin(a)
    var r = matrix_identity_float4x4
    r.columns.0 = SIMD4<Float>(c, 0, -s, 0)
    r.columns.2 = SIMD4<Float>(s, 0, c, 0)
    return m * r
}
@inline(__always) func mRotateZ(_ m: simd_float4x4, _ a: Float) -> simd_float4x4 {
    let c = cos(a), s = sin(a)
    var r = matrix_identity_float4x4
    r.columns.0 = SIMD4<Float>(c, s, 0, 0)
    r.columns.1 = SIMD4<Float>(-s, c, 0, 0)
    return m * r
}
@inline(__always) func mScale(_ m: simd_float4x4, _ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    var s = matrix_identity_float4x4
    s.columns.0.x = x
    s.columns.1.y = y
    s.columns.2.z = z
    return m * s
}
