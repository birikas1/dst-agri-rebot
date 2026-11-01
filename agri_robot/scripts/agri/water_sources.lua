-- Shared source selection for resource previews and actual refill trips.
local U=require("agri/util")
local M={}
function M.Pick(sources,robot)
    local best,best_rank,best_distance
    for _,source in ipairs(sources or {}) do
        local water=U.Valid(source) and source.components and source.components.watersource
        if water and water.available then
            local rank=source:HasTag("agriwell") and 0 or 1
            local distance=robot:GetDistanceSqToInst(source)
            if not best or rank<best_rank or rank==best_rank and
                (distance<best_distance or distance==best_distance and (source.GUID or 0)<(best.GUID or 0)) then
                best,best_rank,best_distance=source,rank,distance
            end
        end
    end
    return best
end
return M
