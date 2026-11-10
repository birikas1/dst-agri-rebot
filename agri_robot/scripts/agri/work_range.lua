-- Work-center range rules and client-local range rings.
--
-- Placement rules (shared by client placer and server build validation via
-- recipe.testfn -> Map:CanDeployRecipeAtPoint):
--   * a robot may only be built inside an existing work center's radius;
--   * a new work center may not be built where its radius overlaps another.
--
-- Ring display follows the vanilla Ice Flingomatic (firesuppressor): the
-- "firefighter_placement" ground ring, PLACER_SCALE 1.55 == 15 world units.
local C=require("agri/constants")
local M={}

M.RING_BANK="firefighter_placement"
-- firesuppressor.lua: PLACER_SCALE 1.55 draws TUNING.FIRE_DETECTOR_RANGE (15).
M.RING_SCALE_PER_UNIT=1.55/15
M.CENTER_TAGS={"agriworkcenter"}
M.CENTER_NOTAGS={"INLIMBO"}
M.RING_COLOUR={0,.2,.5}       -- vanilla flingomatic helper tint
M.RING_ACTIVE_COLOUR={0,.5,.1} -- the center that contains the robot placer

function M.RingScale(radius)
    return (radius or C.DEFAULT_RADIUS)*M.RING_SCALE_PER_UNIT
end

local function maxradius()
    return C.RADII[#C.RADII]
end

-- Radius replicated on a center entity (works on clients and the server).
function M.CenterRadius(center)
    local radius=center and center._agri_radius and center._agri_radius:value()
    if type(radius)~="number" or radius<=0 then radius=C.DEFAULT_RADIUS end
    return radius
end

local function valid(inst)
    return inst~=nil and (inst.IsValid==nil or inst:IsValid())
end

local function centers_near(x,z,reach)
    local out={}
    for _,inst in ipairs(TheSim:FindEntities(x,0,z,reach,M.CENTER_TAGS,M.CENTER_NOTAGS) or {}) do
        if valid(inst) and inst._agri_radius~=nil then out[#out+1]=inst end
    end
    return out
end

local function order(inst)
    local v=inst._agri_order and inst._agri_order:value()
    return type(v)=="number" and v or math.huge
end

-- Oldest work center whose radius contains (x,z), or nil.
function M.FindCenter(x,z,exclude)
    local best
    for _,inst in ipairs(centers_near(x,z,maxradius())) do
        if inst~=exclude then
            local radius=M.CenterRadius(inst)
            local cx,_,cz=inst.Transform:GetWorldPosition()
            if (x-cx)^2+(z-cz)^2<=radius*radius then
                if not best or order(inst)<order(best) then best=inst end
            end
        end
    end
    return best
end

-- True when a center at (x,z) with `radius` would overlap another center.
function M.CenterOverlaps(x,z,radius,exclude)
    radius=radius or C.DEFAULT_RADIUS
    for _,other in ipairs(centers_near(x,z,maxradius()+radius)) do
        if other~=exclude then
            local ox,_,oz=other.Transform:GetWorldPosition()
            local oradius=M.CenterRadius(other)
            if (x-ox)^2+(z-oz)^2<(radius+oradius)^2 then return true,other end
        end
    end
    return false
end

-- Recipe testfns: Recipe.testfn(pt, rot, builder). Called by the client
-- placer (red/green) and again by the server before the build is spawned.
function M.RobotPlacementTest(pt)
    return pt~=nil and M.FindCenter(pt.x,pt.z)~=nil
end
function M.CenterPlacementTest(pt)
    return pt~=nil and not M.CenterOverlaps(pt.x,pt.z,C.DEFAULT_RADIUS)
end

-- Client-local ground ring (never networked, never saved).
function M.CreateRing(radius,parent)
    local ring=CreateEntity()
    ring.entity:SetCanSleep(false)
    ring.persists=false
    ring.entity:AddTransform()
    ring.entity:AddAnimState()
    ring:AddTag("CLASSIFIED")
    ring:AddTag("NOCLICK")
    ring:AddTag("FX")
    ring:AddTag("placer")
    ring.AnimState:SetBank(M.RING_BANK)
    ring.AnimState:SetBuild(M.RING_BANK)
    ring.AnimState:PlayAnimation("idle")
    ring.AnimState:SetLightOverride(1)
    ring.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
    ring.AnimState:SetLayer(LAYER_BACKGROUND)
    ring.AnimState:SetSortOrder(1)
    ring.AnimState:SetAddColour(M.RING_COLOUR[1],M.RING_COLOUR[2],M.RING_COLOUR[3],0)
    if parent then ring.entity:SetParent(parent.entity) end
    M.SetRingRadius(ring,radius)
    return ring
end
function M.SetRingRadius(ring,radius)
    if not ring then return end
    radius=radius or C.DEFAULT_RADIUS
    if ring._agri_radius==radius then return end
    local s=M.RingScale(radius)
    ring.Transform:SetScale(s,s,s)
    ring._agri_radius=radius
end
function M.SetRingActive(ring,active)
    if not ring or ring._agri_active==active then return end
    local c=active and M.RING_ACTIVE_COLOUR or M.RING_COLOUR
    ring.AnimState:SetAddColour(c[1],c[2],c[3],0)
    ring._agri_active=active
end

-- Placed work center (client only): show the ring while the mouse hovers
-- the center, and while any agribot / agriworkcenter placer is nearby
-- (vanilla deployhelper, exactly like flingomatic helpers).
M.HOVER_DISTANCE=1.0
function M.IsHovered(inst)
    if not ThePlayer or not TheInput then return false end
    if TheInput:GetWorldEntityUnderMouse()==inst then return true end
    local highlight=inst.components and inst.components.highlight
    if highlight and highlight.highlit then return true end
    -- Fallback: cursor on the sign's footprint, not over a HUD widget.
    if TheInput.GetHUDEntityUnderMouse and TheInput:GetHUDEntityUnderMouse()~=nil then return false end
    local pos=TheInput.GetWorldPosition and TheInput:GetWorldPosition()
    if pos then
        local x,_,z=inst.Transform:GetWorldPosition()
        if (pos.x-x)^2+(pos.z-z)^2<=M.HOVER_DISTANCE*M.HOVER_DISTANCE then return true end
    end
    return false
end
function M.RefreshCenterRing(inst)
    local want=inst._agri_hover or inst._agri_helper_on
    if want and not inst:IsValid() then want=false end
    if want then
        if not inst._agri_ring or not inst._agri_ring:IsValid() then
            inst._agri_ring=M.CreateRing(M.CenterRadius(inst),inst)
        else
            M.SetRingRadius(inst._agri_ring,M.CenterRadius(inst))
        end
        M.SetRingActive(inst._agri_ring,inst._agri_helper_active==true)
    elseif inst._agri_ring then
        if inst._agri_ring:IsValid() then inst._agri_ring:Remove() end
        inst._agri_ring=nil
    end
end
function M.SetupCenterClient(inst)
    inst:AddComponent("deployhelper")
    local helper=inst.components.deployhelper
    helper:AddRecipeFilter("agribot")
    helper:AddRecipeFilter("agriworkcenter")
    -- The center never sleeps (SetCanSleep(false)), so do not rely on an
    -- engine wake event to enrol it in the global deploy-helper set.
    if helper.OnEntityWake then helper:OnEntityWake() end
    helper.onenablehelper=function(entity,enabled)
        entity._agri_helper_on=enabled and true or nil
        if not enabled then entity._agri_helper_active=nil end
        M.RefreshCenterRing(entity)
    end
    -- Called every frame by an active placer: highlight the center that
    -- would own a robot built at the placer's position.
    helper.onstarthelper=function(entity,recipename,placerinst)
        local active=false
        if recipename=="agribot" and placerinst and placerinst.Transform then
            local px,_,pz=placerinst.Transform:GetWorldPosition()
            active=M.FindCenter(px,pz)==entity
        end
        entity._agri_helper_active=active
        M.RefreshCenterRing(entity)
    end
    inst:AddComponent("updatelooper")
    -- Wall updates keep working while the server is paused.
    inst.components.updatelooper:AddOnWallUpdateFn(function(entity)
        entity=entity or inst
        local hover=M.IsHovered(entity)
        if hover~=(entity._agri_hover==true) or (entity._agri_ring and entity._agri_ring._agri_radius~=M.CenterRadius(entity)) then
            entity._agri_hover=hover or nil
            M.RefreshCenterRing(entity)
        end
    end)
    inst:ListenForEvent("onremove",function(entity)
        entity._agri_hover,entity._agri_helper_on=nil,nil
        M.RefreshCenterRing(entity)
    end)
end

-- Center placer: like firesuppressor_placer the placer itself is the ground
-- ring; the mini-sign art is a linked child scaled back to normal size.
function M.SetupCenterPlacer(inst)
    local s=M.RingScale(C.DEFAULT_RADIUS)
    local sign=CreateEntity()
    sign.entity:SetCanSleep(false)
    sign.persists=false
    sign.entity:AddTransform()
    sign.entity:AddAnimState()
    sign:AddTag("CLASSIFIED")
    sign:AddTag("NOCLICK")
    sign:AddTag("placer")
    sign.Transform:SetScale(1/s,1/s,1/s)
    sign.AnimState:SetBank("sign_mini")
    sign.AnimState:SetBuild("sign_mini")
    sign.AnimState:PlayAnimation("idle")
    sign.AnimState:SetLightOverride(1)
    sign.entity:SetParent(inst.entity)
    inst.components.placer:LinkEntity(sign)
    inst._agri_sign=sign
end

-- Robot placer: centers in range draw their rings through deployhelper;
-- the placer itself stays the vanilla robot art (red outside any center).
function M.SetupPlacer(inst)
    inst.deployhelper_key="agribot"
end
return M
