// Math utilities: scalars, Mat4 projections (Float, Metal clip space
// z∈[0,1]), AABB with axis sweeps, frustum. The projection/frustum forms are
// adjusted from GL to Metal conventions; the renderer uses these directly.

import Foundation
import simd

// ---- scalars -----------------------------------------------------------------
@inline(__always) public func clampD(_ x: Double, _ lo: Double, _ hi: Double) -> Double { x < lo ? lo : (x > hi ? hi : x) }
@inline(__always) public func lerpD(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
@inline(__always) public func degToRad(_ d: Double) -> Double { d * .pi / 180 }

public func wrapDegrees(_ input: Double) -> Double {
    var d = input.truncatingRemainder(dividingBy: 360)
    if d >= 180 { d -= 360 }
    if d < -180 { d += 360 }
    return d
}

@inline(__always)
public func mapRange(_ x: Double, _ a0: Double, _ a1: Double, _ b0: Double, _ b1: Double) -> Double {
    b0 + (b1 - b0) * clampD((x - a0) / (a1 - a0), 0, 1)
}

// ---- Mat4 (Float, column-major, Metal clip space) ------------------------------
public typealias Mat4 = simd_float4x4

/// perspective with Metal depth range z' ∈ [0, 1]
public func mat4Perspective(fovYRad: Float, aspect: Float, near: Float, far: Float) -> Mat4 {
    let f = 1 / tan(fovYRad / 2)
    var m = Mat4(0)
    m[0][0] = f / aspect
    m[1][1] = f
    m[2][2] = far / (near - far)
    m[2][3] = -1
    m[3][2] = (far * near) / (near - far)
    return m
}

/// ortho with Metal depth range z' ∈ [0, 1]
public func mat4Ortho(l: Float, r: Float, b: Float, t: Float, n: Float, f: Float) -> Mat4 {
    var m = Mat4(0)
    m[0][0] = 2 / (r - l)
    m[1][1] = 2 / (t - b)
    m[2][2] = -1 / (f - n)
    m[3][0] = -(r + l) / (r - l)
    m[3][1] = -(t + b) / (t - b)
    m[3][2] = -n / (f - n)
    m[3][3] = 1
    return m
}

public func mat4LookDir(eye: SIMD3<Float>, dir: SIMD3<Float>, up: SIMD3<Float>) -> Mat4 {
    let z = simd_normalize(-dir)
    let x = simd_normalize(simd_cross(up, z))
    let y = simd_cross(z, x)
    return Mat4(columns: (
        SIMD4<Float>(x.x, y.x, z.x, 0),
        SIMD4<Float>(x.y, y.y, z.y, 0),
        SIMD4<Float>(x.z, y.z, z.z, 0),
        SIMD4<Float>(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)
    ))
}

// ---- AABB (Double — collision space) -------------------------------------------
public struct AABB {
    public var x0: Double, y0: Double, z0: Double
    public var x1: Double, y1: Double, z1: Double

    @inline(__always)
    public init(_ x0: Double, _ y0: Double, _ z0: Double, _ x1: Double, _ y1: Double, _ z1: Double) {
        self.x0 = x0; self.y0 = y0; self.z0 = z0
        self.x1 = x1; self.y1 = y1; self.z1 = z1
    }

    @inline(__always)
    public func offset(_ x: Double, _ y: Double, _ z: Double) -> AABB {
        AABB(x0 + x, y0 + y, z0 + z, x1 + x, y1 + y, z1 + z)
    }

    @inline(__always)
    public func expand(_ x: Double, _ y: Double, _ z: Double) -> AABB {
        AABB(x0 - x, y0 - y, z0 - z, x1 + x, y1 + y, z1 + z)
    }

    @inline(__always)
    public func intersects(_ b: AABB) -> Bool {
        x0 < b.x1 && x1 > b.x0 && y0 < b.y1 && y1 > b.y0 && z0 < b.z1 && z1 > b.z0
    }

    @inline(__always)
    public func contains(_ x: Double, _ y: Double, _ z: Double) -> Bool {
        x >= x0 && x < x1 && y >= y0 && y < y1 && z >= z0 && z < z1
    }
}

/// how far box `a` may move along X by `d` before hitting `b`
@inline(__always)
public func sweepX(_ a: AABB, _ b: AABB, _ dIn: Double) -> Double {
    var d = dIn
    if a.y1 <= b.y0 || a.y0 >= b.y1 || a.z1 <= b.z0 || a.z0 >= b.z1 { return d }
    if d > 0 && a.x1 <= b.x0 { let m = b.x0 - a.x1; if m < d { d = m } }
    else if d < 0 && a.x0 >= b.x1 { let m = b.x1 - a.x0; if m > d { d = m } }
    return d
}

@inline(__always)
public func sweepY(_ a: AABB, _ b: AABB, _ dIn: Double) -> Double {
    var d = dIn
    if a.x1 <= b.x0 || a.x0 >= b.x1 || a.z1 <= b.z0 || a.z0 >= b.z1 { return d }
    if d > 0 && a.y1 <= b.y0 { let m = b.y0 - a.y1; if m < d { d = m } }
    else if d < 0 && a.y0 >= b.y1 { let m = b.y1 - a.y0; if m > d { d = m } }
    return d
}

@inline(__always)
public func sweepZ(_ a: AABB, _ b: AABB, _ dIn: Double) -> Double {
    var d = dIn
    if a.x1 <= b.x0 || a.x0 >= b.x1 || a.y1 <= b.y0 || a.y0 >= b.y1 { return d }
    if d > 0 && a.z1 <= b.z0 { let m = b.z0 - a.z1; if m < d { d = m } }
    else if d < 0 && a.z0 >= b.z1 { let m = b.z1 - a.z0; if m > d { d = m } }
    return d
}

/// ray vs AABB; returns t or -1
public func rayAABB(_ ox: Double, _ oy: Double, _ oz: Double, _ dx: Double, _ dy: Double, _ dz: Double, _ b: AABB) -> Double {
    var tmin = -Double.infinity, tmax = Double.infinity
    if abs(dx) < 1e-12 { if ox < b.x0 || ox > b.x1 { return -1 } }
    else {
        var t1 = (b.x0 - ox) / dx, t2 = (b.x1 - ox) / dx
        if t1 > t2 { swap(&t1, &t2) }
        tmin = max(tmin, t1); tmax = min(tmax, t2)
    }
    if abs(dy) < 1e-12 { if oy < b.y0 || oy > b.y1 { return -1 } }
    else {
        var t1 = (b.y0 - oy) / dy, t2 = (b.y1 - oy) / dy
        if t1 > t2 { swap(&t1, &t2) }
        tmin = max(tmin, t1); tmax = min(tmax, t2)
    }
    if abs(dz) < 1e-12 { if oz < b.z0 || oz > b.z1 { return -1 } }
    else {
        var t1 = (b.z0 - oz) / dz, t2 = (b.z1 - oz) / dz
        if t1 > t2 { swap(&t1, &t2) }
        tmin = max(tmin, t1); tmax = min(tmax, t2)
    }
    if tmax < tmin || tmax < 0 { return -1 }
    return tmin >= 0 ? tmin : tmax
}

// ---- frustum (Float, Metal clip space) ------------------------------------------
/// the six clip planes (a, b, c, d) of a view-projection matrix. Unnormalized:
/// culling only tests which side of a plane a corner is on. Stored inline, not
/// in an array, since the renderer builds two of these every frame.
public struct Frustum {
    public var left = SIMD4<Float>(), right = SIMD4<Float>()
    public var bottom = SIMD4<Float>(), top = SIMD4<Float>()
    public var near = SIMD4<Float>(), far = SIMD4<Float>()

    public init() {}

    public mutating func setFromMatrix(_ m: Mat4) {
        // rows of the column-major matrix
        let r0 = SIMD4<Float>(m[0][0], m[1][0], m[2][0], m[3][0])
        let r1 = SIMD4<Float>(m[0][1], m[1][1], m[2][1], m[3][1])
        let r2 = SIMD4<Float>(m[0][2], m[1][2], m[2][2], m[3][2])
        let r3 = SIMD4<Float>(m[0][3], m[1][3], m[2][3], m[3][3])
        // Metal clip: -w ≤ x,y ≤ w and 0 ≤ z ≤ w → near plane is r2 alone
        left = r3 + r0; right = r3 - r0
        bottom = r3 + r1; top = r3 - r1
        near = r2; far = r3 - r2
    }

    /// false when the box is wholly outside one plane
    @inline(__always)
    public func intersectsBox(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float) -> Bool {
        // the box corner furthest along the plane's normal
        @inline(__always) func inside(_ p: SIMD4<Float>) -> Bool {
            p.x * (p.x > 0 ? x1 : x0) + p.y * (p.y > 0 ? y1 : y0) + p.z * (p.z > 0 ? z1 : z0) + p.w >= 0
        }
        return inside(left) && inside(right) && inside(bottom) && inside(top) && inside(near) && inside(far)
    }
}
