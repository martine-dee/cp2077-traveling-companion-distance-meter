-- The data structure
travelingCompanionDistanceMeter = {
    lastPos = {
        x,
        y,
        z,
        timeTick,
    },
    speedPoints = {
        speedPos,
        speedSize,
        speedVals,
        speedReady,
        totalLength,
        totalTime,
    },
    state = {
        frameCounter,
        displayed,
    },
	output = {
		distanceTraveled,
		immediateSpeed,
        topImmediateSpeed,
        speed,
        topSpeed,
	},
};

-- The c-tor
function travelingCompanionDistanceMeter:new()
    -- Initialize the travelingCompanionDistanceMeter
    registerForEvent('onInit', function()
        self:clear(true);
    end)

    -- Reset the travelingCompanionDistanceMeter
    registerHotkey("tcdmReset", "Reset TCDM", function()
        self:clear(false);
    end)

    -- Toggle the travelingCompanionDistanceMeter
    registerHotkey("tcdmMeterToggle", "Toggle TCDM", function()
        self:toggleDisplayed();
    end)

    -- The main loop
    registerForEvent('onDraw', function()
        -- Don't enter here if the player isn't in the game
        if self:isOutsideTheGame() then
            return;
        end

        -- Show the UI
        if(self:isDisplayed()) then
            self:showTheUI();
        end

        -- Literally the frame counter, as long as the notInGame func is false
        self.state.frameCounter = self.state.frameCounter + 1;

        -- Do the computation only on every few frames in
        if(self.state.frameCounter % 2 ~= 0) then
            return;
        end

        -- Collect all the external data
        local currPos = Game.GetPlayer():GetWorldPosition();
        local currTime = os.clock(); -- Game.GetSimTime():ToFloat() too, but it's quite imprecise

        -- Only deal with speed if the tool is displayed
        if(self:isDisplayed()) then
        end

        -- Only compute things if this isn't the first frame
        if(self.lastPos.timeTick ~= -1) then
            -- Compute the length between the currPos and the lastPos
            local length = math.sqrt(
                (currPos.x - self.lastPos.x)^2
                + (currPos.y - self.lastPos.y)^2
                + (currPos.z - self.lastPos.z)^2
            );

            -- Actually, skip anything and everything if the length isn't sufficient
            if length > 0.001 then
                -- Update distance traveled
                self.output.distanceTraveled = self.output.distanceTraveled + length;

                -- Only compute the speed-related info if the tool is displayed
                if(self:isDisplayed()) then
                    local timeDiff = currTime - self.lastPos.timeTick;

                    -- Update the immediate speed info, if displayed
                    self.output.immediateSpeed = (length / timeDiff) * 3.6; -- metres per second converted to km/h
                    if(self.output.topImmediateSpeed < self.output.immediateSpeed) then
                        self.output.topImmediateSpeed = self.output.immediateSpeed;
                    end

                    -- Manage the speed points and derived data
                    self.speedPoints.speedPos = self.speedPoints.speedPos + 1;
                    if(self.speedPoints.speedPos == self.speedPoints.speedSize + 1) then
                        self.speedPoints.speedReady = true;
                        self.speedPoints.speedPos = 1;
                    end

                    self.speedPoints.speedVals[self.speedPoints.speedPos][1] = currPos.x;
                    self.speedPoints.speedVals[self.speedPoints.speedPos][2] = currPos.y;
                    self.speedPoints.speedVals[self.speedPoints.speedPos][3] = currPos.z;
                    self.speedPoints.speedVals[self.speedPoints.speedPos][4] = currTime;
                    self.speedPoints.speedVals[self.speedPoints.speedPos][5] = length;
                end

                -- Compute the complex speed if applicable
                if(self.speedPoints.speedReady) then
                    local theOldestPost = self.speedPoints.speedPos + 1;
                    if theOldestPost == self.speedPoints.speedSize + 1 then
                        theOldestPost = 1;
                    end

                    local totalLength = 0;
                    local totalTime = self.speedPoints.speedVals[self.speedPoints.speedPos][4] - self.speedPoints.speedVals[theOldestPost][4];
                    for i=1,self.speedPoints.speedSize do
                        totalLength = totalLength + self.speedPoints.speedVals[i][5];
                    end

                    -- Otherwise perform the computations
                    self.output.speed = 3.6 * totalLength / totalTime;

                    -- Update the top speed (where applicable)
                    if(self.output.topSpeed < self.output.speed) then
                        self.output.topSpeed = self.output.speed;
                    end
                end
            else
                self.output.speed = 0;
                self.output.immediateSpeed = 0;
            end
        end

        -- Update all values for the next iteration
        self.lastPos.x = currPos.x;
        self.lastPos.y = currPos.y;
        self.lastPos.z = currPos.z;
        self.lastPos.timeTick = currTime;
    end)

    return self;
end

--------------------------------------------------------------------------------
-- UI --------------------------------------------------------------------------
--------------------------------------------------------------------------------

-- Displays the travelingCompanionDistanceMeter UI
function travelingCompanionDistanceMeter:showTheUI()
    ImGui.SetNextWindowPos(50, 50, ImGuiCond.Always);
    ImGui.SetNextWindowSize(380, 130, ImGuiCond.Always);
    ImGui.PushStyleColor(ImGuiCol.Text, 0xFF00DDFF); -- 0xAABBGGRR
    ImGui.PushStyleColor(ImGuiCol.WindowBg, 0x99000000);
    ImGui.PushStyleColor(ImGuiCol.Border, 0x00000000);        
	
    if ImGui.Begin("TCDM") then
        ImGui.SetWindowFontScale(1.15);
        ImGui.Text("Traveled: " .. string.format(
            "%.5f", self.output.distanceTraveled) .. " m\n"
            .. string.format("% 5.0f km/h (immediate); top=%.2f km/h\n", self.output.immediateSpeed, self.output.topImmediateSpeed)
            .. string.format("% 5.0f km/h (trailing); top=%.2f km/h\n", self.output.speed, self.output.topSpeed)
            .. string.format("x=%.2f y=%.2f z=%.2f t=%.3f", self.lastPos.x, self.lastPos.y, self.lastPos.z, self.lastPos.timeTick)
        );
        ImGui.SetWindowFontScale(1.0);
    end
	
    ImGui.PopStyleColor();
    ImGui.PopStyleColor();
    ImGui.PopStyleColor();
    ImGui.End();
end

--------------------------------------------------------------------------------
-- Helpers ---------------------------------------------------------------------
--------------------------------------------------------------------------------

-- Tells if the travelingCompanionDistanceMeter should be displayed
function travelingCompanionDistanceMeter:isDisplayed()
    return self.state.displayed;
end

-- Toggles whether the travelingCompanionDistanceMeter should be displayed
function travelingCompanionDistanceMeter:toggleDisplayed()
    self.state.displayed = not self.state.displayed;
end

-- Tells if the player is *not* in the game
function travelingCompanionDistanceMeter:isOutsideTheGame()
    return
        Game == nil
        or Game.GetPlayer() == nil
        or Game.GetSystemRequestsHandler():IsPreGame()
        or Game.GetSystemRequestsHandler():IsGamePaused()
        or Game.GetPhotoModeSystem():IsPhotoModeActive()
    ;
end

-- Clear the object; the only option that may avoid this is the
-- :isDisplayed() state of the window
function travelingCompanionDistanceMeter:clear(alsoResetDisplayedState)
    self.output.distanceTraveled = 0;
    self.output.immediateSpeed = 0;
    self.output.topImmediateSpeed = 0;
    self.output.speed = 0;
    self.output.topSpeed = 0;
    self.state.frameCounter = 0;
    if(alsoResetDisplayedState) then
        self.state.displayed = false; -- The companion isn't displayed by default
    end

    self.lastPos.timeTick = -1.0;
    self.lastPos.x = 0;
    self.lastPos.y = 0;
    self.lastPos.z = 0;

    -- Speed points
    self.speedPoints.speedPos = 0;
    self.speedPoints.speedSize = 12;
    self.speedPoints.speedVals = {};
    self.speedPoints.totalLength = 0;
    self.speedPoints.totalTime = 0;
    for i=1,self.speedPoints.speedSize do
        self.speedPoints.speedVals[i] = {0, 0, 0, 0, 0}; -- x, y, z, t, l
    end
    self.speedPoints.speedReady = false;
end

-- Produce and return the object for CET to work with
return travelingCompanionDistanceMeter:new();