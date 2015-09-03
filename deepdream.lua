-- Original by @eladhoffer at https://github.com/eladhoffer/DeepDream.torch.
-- Modifications by @bamos at https://github.com/bamos/dream-art.

local Normalization = {mean = 118.380948/255, std = 61.896913/255}

local M = {}

function reduceNet(full_net,end_layer)
   local net = nn.Sequential()
   for l=1,end_layer do
      net:add(full_net:get(l))
   end
   return net
end

function make_step(net, img, is_cuda, clip, step_size, jitter)
   local step_size = step_size or 0.01
   local jitter = jitter or 32
   local clip = clip
   if clip == nil then clip = true end

   local ox = 0--2*jitter - math.random(jitter)
   local oy = 0--2*jitter - math.random(jitter)
   img = image.translate(img,ox,oy) -- apply jitter shift
   local dst, g
   if is_cuda then
      local cuda_img = img:cuda():view(1,img:size(1),img:size(2),img:size(3))
      dst = net:forward(cuda_img)
      g = net:updateGradInput(cuda_img,dst):double():squeeze()
   else
      dst = net:forward(img)
      g = net:updateGradInput(img,dst)
   end
   -- apply normalized ascent step to the input image
   img:add(g:mul(step_size/torch.abs(g):mean()))

   img = image.translate(img,-ox,-oy) -- apply jitter shift
   if clip then
      bias = Normalization.mean/Normalization.std
      img:clamp(-bias,1/Normalization.std-bias)
   end
   return img
end

function M.deepdream(net, base_img, is_cuda, iter_n, octave_n, octave_scale,
                     end_layer, clip)
   local iter_n = iter_n or 10
   local octave_n = octave_n or 4
   local octave_scale = octave_scale or 1.4
   local end_layer = end_layer or 20
   local net = reduceNet(net, end_layer)
   local clip = clip
   if clip == nil then clip = true end
   -- prepare base images for all octaves
   local octaves = {}
   octaves[octave_n] = torch.add(base_img, -Normalization.mean):div(Normalization.std)
   local _,h,w = unpack(base_img:size():totable())

   for i=octave_n-1,1,-1 do
      octaves[i] = image.scale(octaves[i+1], math.ceil((1/octave_scale)*w), math.ceil((1/octave_scale)*h),'simple')
   end


   local detail
   local src

   for octave, octave_base in pairs(octaves) do
      print("deepdream.octave:",octave)
      src = octave_base
      local _,h1,w1 = unpack(src:size():totable())
      if octave > 1 then
         -- upscale details from the previous octave
         detail = image.scale(detail, w1, h1,'simple')
         src:add(detail)
      end
      for i=1,iter_n do
         if math.fmod(i-1,10) == 0 then print("  deepdream.iter:",i) end
         src = make_step(net, src, is_cuda, clip)
      end
      -- extract details produced on the current octave
      detail = src-octave_base
   end
   -- returning the resulting image
   src:mul(Normalization.std):add(Normalization.mean)
   return src
end

return M
