default (i32, f32)

struct F32 {
  type t = f32

  struct D2 {
    type point = (t, t)
  }

  struct D3 {
    type point = (t, t, t)
    type angles = (t, t, t)
  }
  
  fun min (a : t) (b : t) : t =
    if a < b
    then a
    else b
  
  fun max (a : t) (b : t) : t =
    if a > b
    then a
    else b

  fun min3 (a : t) (b : t) (c : t) : t =
    min (min a b) c

  fun max3 (a : t) (b : t) (c : t) : t =
    max (max a b) c

  fun abso (a : t) : t =
    if a < 0.0
    then -a
    else a

  fun mod (a : t, m : t) : t =
    a - f32 (i32 (a / m)) * m
}

struct I32 {
  type t = i32

  struct D2 {
    type point = (t, t)
  }

  struct D3 {
    type point = (t, t, t)
  }

  -- I know this is silly, but I wanted to try it.
  fun _signum_if_lt (a : t) (b : t) (case_then : t) (case_else : t) : t =
    let factor_then = (signum (b - a) + 1) / 2
    let factor_else = (signum (a - b) + 1) / 2 + signum (a - b) * signum (b - a) + 1
    in case_then * factor_then + case_else * factor_else
  
  fun min (a : t) (b : t) : t =
    _signum_if_lt a b a b 
  
  fun max (a : t) (b : t) : t =
    _signum_if_lt b a a b 

  fun min3 (a : t) (b : t) (c : t) : t =
    min (min a b) c

  fun max3 (a : t) (b : t) (c : t) : t =
    max (max a b) c
}

type triangle = (F32.D3.point, F32.D3.point, F32.D3.point)
type point_projected = (i32, i32, f32)
type triangle_projected = (point_projected, point_projected, point_projected)
type point_barycentric = (i32, I32.D3.point, F32.D3.point)
type camera = (F32.D3.point, F32.D3.angles)
type pixel = u32
type pixel_channel = u32

fun pixel_get_r (p : pixel) : pixel_channel =
  (p >> 16u32) & 255u32

fun pixel_get_g (p : pixel) : pixel_channel =
  (p >> 8u32) & 255u32

fun pixel_get_b (p : pixel) : pixel_channel =
  p & 255u32

fun pixel_to_rgb (p : pixel) : (pixel_channel, pixel_channel, pixel_channel) =
  (pixel_get_r p, pixel_get_g p, pixel_get_b p)

fun rgb_to_pixel (r : pixel_channel, g : pixel_channel, b : pixel_channel) : pixel =
  (r << 16u32) | (g << 8u32) | b

fun hsv_to_rgb (h : f32, s : f32, v : f32) : (pixel_channel, pixel_channel, pixel_channel) =
  let c = v * s
  let h' = h / 60.0
  let x = c * (1.0 - F32.abso (F32.mod (h', 2.0) - 1.0))
  let (r0, g0, b0) = if 0.0 <= h' && h' < 1.0
                     then (c, x, 0.0)
                     else if 1.0 <= h' && h' < 2.0
                     then (x, c, 0.0)
                     else if 2.0 <= h' && h' < 3.0
                     then (0.0, c, x)
                     else if 3.0 <= h' && h' < 4.0
                     then (0.0, x, c)
                     else if 4.0 <= h' && h' < 5.0
                     then (x, 0.0, c)
                     else if 5.0 <= h' && h' < 6.0
                     then (c, 0.0, x)
                     else (0.0, 0.0, 0.0)
  let m = v - c
  let (r, g, b) = (r0 + m, g0 + m, b0 + m)
  in (u32 (255.0 * r), u32 (255.0 * g), u32 (255.0 * b))

fun floor (t : f32) : i32 =
  i32 t

fun ceil (t : f32) : i32 =
  i32 t + 1

fun bound (max : i32) (t : i32) : i32 =
  I32.min (max - 1) (I32.max 0 t)
  
fun project_point
  (w : i32) (h : i32)
  (camera : camera)
  ((x, y, z) : F32.D3.point)
  : I32.D2.point =
  let ((xc, yc, zc), (ax, ay, az)) = camera
  let view_dist = 600.0
  let z_ratio = (view_dist + z) / view_dist

  let w_half = f32 w / 2.0
  let h_half = f32 h / 2.0
  let x_norm = x - w_half
  let y_norm = y - h_half

  let x_norm_projected = x_norm / z_ratio
  let y_norm_projected = y_norm / z_ratio
  let x_projected = x_norm_projected + w_half
  let y_projected = y_norm_projected + h_half
  
  in (i32 x_projected, i32 y_projected)

fun in_range (t : i32) (a : i32) (b : i32) : bool =
  (a < b && a <= t && t <= b) || (b <= a && b <= t && t <= a)
  
fun barycentric_coordinates
  (triangle : triangle_projected)
  ((x, y) : I32.D2.point)
  : point_barycentric =
  let ((xp0, yp0, _z0), (xp1, yp1, _z1), (xp2, yp2, _z2)) = triangle
  let factor = (yp1 - yp2) * (xp0 - xp2) + (xp2 - xp1) * (yp0 - yp2)
  let a = ((yp1 - yp2) * (x - xp2) + (xp2 - xp1) * (y - yp2))
  let b = ((yp2 - yp0) * (x - xp2) + (xp0 - xp2) * (y - yp2))
  let c = factor - a - b
  let factor' = f32 factor
  let an = f32 a / factor'
  let bn = f32 b / factor'
  let cn = 1.0 - an - bn
  in (factor, (a, b, c), (an, bn, cn))

fun is_inside_triangle
  ((factor, (a, b, c), (_an, _bn, _cn)) : point_barycentric)
  : bool =
  in_range a 0 factor && in_range b 0 factor && in_range c 0 factor

fun is_in_front_of_camera (z : f32) : bool =
  z >= 0.0

fun interpolate_z
  (triangle : triangle_projected)
  ((_factor, (_a, _b, _c), (an, bn, cn)) : point_barycentric)
  : f32 =
  let ((_xp0, _yp0, z0), (_xp1, _yp1, z1), (_xp2, _yp2, z2)) = triangle
  in an * z0 + bn * z1 + cn * z2

fun render_triangle
  (camera : camera)
  (triangle : triangle)
  (frame : *[w][h]pixel)
  : [w][h]pixel =
  let ((x0, y0, z0), (x1, y1, z1), (x2, y2, z2)) = triangle
  let (xp0, yp0) = project_point w h camera (x0, y0, z0)
  let (xp1, yp1) = project_point w h camera (x1, y1, z1)
  let (xp2, yp2) = project_point w h camera (x2, y2, z2)
  let triangle_projected = ((xp0, yp0, z0), (xp1, yp1, z1), (xp2, yp2, z2))

  let x_min = bound w (I32.min3 xp0 xp1 xp2)
  let x_max = bound w (I32.max3 xp0 xp1 xp2)
  let y_min = bound h (I32.min3 yp0 yp1 yp2)
  let y_max = bound h (I32.max3 yp0 yp1 yp2)
  let x_diff = x_max - x_min
  let y_diff = y_max - y_min
  let x_range = map (+ x_min) (iota x_diff)
  let y_range = map (+ y_min) (iota y_diff)

  let bbox_coordinates =
    reshape (x_diff * y_diff)
    (map (fn (x : i32) : [](i32, i32) =>
            map (fn (y : i32) : (i32, i32) =>
                   (x, y))
                y_range)
         x_range)
  let bbox_indices =
    map (fn ((x, y) : (i32, i32)) : i32 =>
           x * h + y)
        bbox_coordinates

  let barys = map (barycentric_coordinates triangle_projected)
                  bbox_coordinates
  let z_values = map (interpolate_z triangle_projected)
                     barys
  let mask0 = map is_inside_triangle barys
  let mask1 = map is_in_front_of_camera z_values
  let mask = zipWith (&&) mask0 mask1

  let (write_indices, write_values) =
    unzip (zipWith (fn (index : i32)
                       (z : f32)
                       (inside : bool)
                       : (i32, pixel) =>
                      if inside
                      then let h = 120.0
                           let s = 0.8
                           let v = F32.min 1.0 (1.0 / (z * 0.01))
                           let rgb = hsv_to_rgb (h, s, v)
                           let pixel = rgb_to_pixel rgb
                           in (index, pixel)
                      else (-1, 0u32))
                   bbox_indices z_values mask)
  let pixels = reshape (w * h) frame
  let pixels' = write write_indices write_values pixels
  let frame' = reshape (w, h) pixels'
  in frame'

fun rotate_point
  ((angle_x, angle_y, angle_z) : F32.D3.angles)
  ((x_origo, y_origo, z_origo) : F32.D3.point)
  ((x, y, z) : F32.D3.point)
  : F32.D3.point =
  let (x0, y0, z0) = (x - x_origo, y - y_origo, z - z_origo)

  let (sin_x, cos_x) = (sin32 angle_x, cos32 angle_x)
  let (sin_y, cos_y) = (sin32 angle_y, cos32 angle_y)
  let (sin_z, cos_z) = (sin32 angle_z, cos32 angle_z)

  -- X axis.
  let (x1, y1, z1) = (x0,
                      y0 * cos_x - z0 * sin_x,
                      y0 * sin_x + z0 * cos_x)
  -- Y axis.
  let (x2, y2, z2) = (z1 * sin_y + x1 * cos_y,
                      y1,
                      z1 * cos_y - x1 * sin_y)
  -- Z axis.
  let (x3, y3, z3) = (x2 * cos_z - y2 * sin_z,
                      x2 * sin_z + y2 * cos_z,
                      z2)

  let (x', y', z') = (x_origo + x3, y_origo + y3, z_origo + z3)
  in (x', y', z')

entry rotate_point_raw
  (angle_x : f32, angle_y : f32, angle_z : f32,
   x_origo : f32, y_origo : f32, z_origo : f32,
   x : f32, y : f32, z : f32) : (f32, f32, f32) =
  rotate_point (angle_x, angle_y, angle_z) (x_origo, y_origo, z_origo) (x, y, z)
  
  
entry test
  (
   f : *[w][h]pixel,
   x0 : f32, y0 : f32, z0 : f32,
   x1 : f32, y1 : f32, z1 : f32,
   x2 : f32, y2 : f32, z2 : f32
  ) : [w][h]pixel =
  let t = ((x0, y0, z0), (x1, y1, z1), (x2, y2, z2))
  let c = ((0.0, 0.0, 0.0), (0.0, 0.0, 0.0))
  in render_triangle c t f
