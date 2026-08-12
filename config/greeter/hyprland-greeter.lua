-- Vexyon greeter — kiosk Hyprland config for greetd (Lua, Hyprland >= 0.55)
-- (installed to /etc/greetd/vexyon-greeter/hyprland.lua)
--
-- Runs the Quickshell greeter and exits the compositor when it quits —
-- Greetd.launch(..., quit=true) makes qs exit after posting start_session,
-- and greetd then starts the real user session on this VT.

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "1" })

-- Pin de GPU compartido con la sesión de usuario (GENERADO por install.sh y
-- reescrito por vexyon-gpu-hotplug en hotplugs iGPU/dGPU; en máquinas de una
-- sola GPU es solo un comentario informativo). require() resuelve relativo a
-- este fichero: /etc/greetd/vexyon-greeter/vexyon-gpu.lua.
require("vexyon-gpu")

-- install.sh sustituye el valor por behavior.keyboardLayout del usuario —
-- la contraseña debe teclearse con la misma distribución que en la sesión.
hl.config({
    input = {
        kb_layout = "us",
    },

    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        force_default_wallpaper = 0,
    },

    decoration = {
        blur = { enabled = false },
        shadow = { enabled = false },
    },

    animations = {
        enabled = false,
    },
})

-- greeter surface + compositor lifetime tied to qs. La forma clásica
-- `hyprctl dispatch exit` NO funciona en roots Lua.
hl.on("hyprland.start", function()
    hl.exec_cmd("sh -c \"qs -p /etc/greetd/vexyon-greeter; hyprctl dispatch 'hl.dsp.exit()'\"")
end)
