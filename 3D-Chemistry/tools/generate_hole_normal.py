from PIL import Image, ImageDraw
import math
import random

# 生成带环形渐变和随机噪声的法线贴图
# size: 图片尺寸（方形）
# strength: 凹槽强度（0..1）

def generate_normal_map(size=512, strength=0.6, noise_scale=0.02):
    w = h = size
    cx = (w - 1) / 2.0
    cy = (h - 1) / 2.0
    radius = min(cx, cy) * 0.95

    img = Image.new('RGBA', (w, h))
    px = img.load()

    for y in range(h):
        for x in range(w):
            dx = (x - cx) / radius
            dy = (y - cy) / radius
            dist2 = dx*dx + dy*dy

            if dist2 <= 1.0:
                # 基于距离的环形曲率（更接近边缘时斜率更大）
                # 我们构造一个凹槽：z = sqrt(1 - (dist^p) * strength)
                p = 1.5
                k = max(0.0, min(1.0, strength))
                inner = max(0.0, 1.0 - math.pow(dist2, p) * k)
                dz = math.sqrt(inner)

                # 法线方向近似为 (dx*k, dy*k, dz) 然后归一化
                vx = dx * k
                vy = dy * k
                vz = dz
                vlen = math.sqrt(vx*vx + vy*vy + vz*vz)
                if vlen > 1e-6:
                    vx /= vlen
                    vy /= vlen
                    vz /= vlen
            else:
                vx, vy, vz = 0.0, 0.0, 1.0

            # 加入细微随机噪声
            nx = vx + (random.random() - 0.5) * noise_scale
            ny = vy + (random.random() - 0.5) * noise_scale
            nz = vz
            nlen = math.sqrt(nx*nx + ny*ny + nz*nz)
            if nlen > 1e-6:
                nx /= nlen
                ny /= nlen
                nz /= nlen

            # 转换到 [0,255]
            r = int((nx * 0.5 + 0.5) * 255)
            g = int((ny * 0.5 + 0.5) * 255)
            b = int((nz * 0.5 + 0.5) * 255)
            a = 255
            px[x, y] = (r, g, b, a)

    return img

if __name__ == '__main__':
    img = generate_normal_map(size=512, strength=0.6, noise_scale=0.02)
    img.save('HoleNormal.png')
    print('Saved HoleNormal.png')
