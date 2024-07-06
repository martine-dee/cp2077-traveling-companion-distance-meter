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
        uiScale,
    },
    constants = {
        std_gravity_pos = 9.80665, -- m/s^2; inverted sign
        display_update_interval = 0.15, -- seconds
    },
	output = {
		distanceTraveled,
        speed,
        topSpeed,
        displayedSpeed,
        displayedSpeedTime,
        accel,              -- Acceleration vector (xyz Gs)
        accelint,           -- Acceleration intensity (Gs)
        displayedAccel,     -- The displayed acceleration intensity (Gs)
        displayedAccelTime, -- The last time displayed acceleration was updated
        accelMax,           -- The maximal recorded acceleration intensity (Gs)
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

        if(self.state.frameCounter % 79 == 0) then
            self:refreshUIScale();
        end

        -- Do the computation only on every few frames in
        if(self.state.frameCounter % 2 ~= 0) then
            return;
        end

        -- Collect all the external data
        local currPos = Game.GetPlayer():GetWorldPosition();
        local currTime = os.clock(); -- Game.GetSimTime():ToFloat() too, but it's quite imprecise

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

                    -------------------------------------------
                    -- Manage the speed points and derived data
                    -------------------------------------------
                    self.speedPoints.speedPos = self.speedPoints.speedPos + 1;
                    if(self.speedPoints.speedPos == self.speedPoints.speedSize + 1) then
                        self.speedPoints.speedPos = 1;

                        -- Once the speeds have become ready, compute the sum of all lengths
                        -- But, do this only if the speeds aren't marked as ready yet
                        if(not self.speedPoints.speedReady) then 
                            self.speedPoints.speedReady = true;
                            self.speedPoints.totalLength = 0;
                            for i=1,self.speedPoints.speedSize do
                                self.speedPoints.totalLength = self.speedPoints.totalLength + self.speedPoints.speedVals[i][5];
                            end
                        end
                    end

                    -- Maintain the .totalTime
                    local theOldestPos = self.speedPoints.speedPos + 1;
                    if theOldestPos == self.speedPoints.speedSize + 1 then
                        theOldestPos = 1;
                    end
                    self.speedPoints.totalTime = currTime - self.speedPoints.speedVals[theOldestPos][4];

                    -- Maintain the .totalLength
                    -- Remove the length from the point that will be overwritten
                    -- and add length of the point that will be added in its place
                    self.speedPoints.totalLength =
                        self.speedPoints.totalLength
                        - self.speedPoints.speedVals[self.speedPoints.speedPos][5]
                        + length
                    ;

                    -- Write the new point
                    self.speedPoints.speedVals[self.speedPoints.speedPos][1] = currPos.x;
                    self.speedPoints.speedVals[self.speedPoints.speedPos][2] = currPos.y;
                    self.speedPoints.speedVals[self.speedPoints.speedPos][3] = currPos.z;
                    self.speedPoints.speedVals[self.speedPoints.speedPos][4] = currTime;
                    self.speedPoints.speedVals[self.speedPoints.speedPos][5] = length;
                end

                -- Compute the values derived from speed points if all of them are ready
                if(self.speedPoints.speedReady) then
                    -- Compute the output speed
                    self.output.speed = 3.6 * self.speedPoints.totalLength / self.speedPoints.totalTime;

                    -- Update the top speed (where applicable)
                    if(self.output.topSpeed < self.output.speed) then
                        self.output.topSpeed = self.output.speed;
                    end

                    -- Update the displayed speed
                    if((self.output.displayedSpeedTime == -1) or (currTime - self.output.displayedSpeedTime) > self.constants.display_update_interval) then
                        self.output.displayedSpeed = self.output.speed;
                        self.output.displayedSpeedTime = currTime;
                    end

                    -- Update acceleration's internal and displayed values
                    -- ... if TCDM is displayed.
                    if(self:isDisplayed()) then
                        -- The index of the oldest data point
                        local v1pos = self.speedPoints.speedPos+1;
                        if v1pos > self.speedPoints.speedSize then
                            v1pos = 1;
                        end

                        -- The index of the newest data point
                        local v2pos = self.speedPoints.speedPos;

                        -- The time difference to fulfill $vvec
                        local tdiff = self.speedPoints.speedVals[v2pos][4] - self.speedPoints.speedVals[v1pos][4];

                        -- Record the movement vector and $tdiff for later use
                        self.speedPoints.speedVals[self.speedPoints.speedPos][7] = {
                            -- The space vector from the oldest to the newest data point
                            {
                                self.speedPoints.speedVals[v2pos][1] - self.speedPoints.speedVals[v1pos][1],
                                self.speedPoints.speedVals[v2pos][2] - self.speedPoints.speedVals[v1pos][2],
                                self.speedPoints.speedVals[v2pos][3] - self.speedPoints.speedVals[v1pos][3],
                            },
                            tdiff,
                            {0, 0, 0}, -- Slot for acceleration vector, in m/s^2
                            0,         -- Slot for acceleration intensity, in m/s^2
                        };

                        -- If the oldest data point has been initialized, then computation
                        -- of acceleration values can begin. To check this, $tdiff of the
                        -- oldest point in the dataset is used. It ought to be greater
                        -- than zero.
                        if(self.speedPoints.speedVals[v1pos][7][2] > 0) then
                            -- The oldest data point (speed diff vs time)
                            local vvec1 = self.speedPoints.speedVals[v1pos][7][1];
                            local t1 = self.speedPoints.speedVals[v1pos][7][2];

                            -- The newest data point (speed diff vs time)
                            local vvec2 = self.speedPoints.speedVals[v2pos][7][1];
                            local t2 = self.speedPoints.speedVals[v2pos][7][2];

                            -- The time difference between the two said data points
                            local tdiff = self.speedPoints.speedVals[v2pos][4] - self.speedPoints.speedVals[v1pos][4];

                            -- The acceleration vector,
                            -- i.e. the speed difference between the two data points, per time
                            local vaccel = {
                                (vvec2[1]/t2 - vvec1[1]/t1) / tdiff,
                                (vvec2[2]/t2 - vvec1[2]/t1) / tdiff,
                                (vvec2[3]/t2 - vvec1[3]/t1) / tdiff + self.constants.std_gravity_pos,
                            };

                            -- Write the acceleration vector and its intensity to the current data point
                            self.speedPoints.speedVals[v2pos][7][3] = vaccel;
                            self.speedPoints.speedVals[v2pos][7][4] = math.sqrt(vaccel[1]^2 + vaccel[2]^2 + vaccel[3]^2);

                            -- Write the acceleration vector and intensity (in Gs)
                            -- into the self.output section
                            self.output.accel[1] = vaccel[1] / self.constants.std_gravity_pos;
                            self.output.accel[2] = vaccel[2] / self.constants.std_gravity_pos;
                            self.output.accel[3] = vaccel[3] / self.constants.std_gravity_pos;
                            self.output.accelint = self.speedPoints.speedVals[v2pos][7][4] / self.constants.std_gravity_pos;

                            -- Update the displayed acceleration at regular intervals
                            if((self.output.displayedAccelTime == -1)
                                or ((currTime - self.output.displayedAccelTime) > self.constants.display_update_interval)
                            ) then
                                self.output.displayedAccel = self.output.accelint;
                                self.output.displayedAccelTime = currTime;
                            end

                            -- Maintain the value of maximum recorded acceleration
                            if(self.output.accelint > self.output.accelMax) then
                                self.output.accelMax = self.output.accelint;
                            end
                        end
                    end
                end
            else
                -- Set all for the standing still values
                self.output.speed = 0;
                self.output.displayedSpeed = 0;
                self.output.displayedAccel = 1;
                self.output.accelint = 0;
                self.output.accel[1] = 0;
                self.output.accel[2] = 0;
                self.output.accel[3] = -1;
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

function travelingCompanionDistanceMeter:refreshUIScale()
    local displayWidth, displayHeight = GetDisplayResolution();
    self.state.uiScale = displayHeight / 1080.0;
end

-- Displays the travelingCompanionDistanceMeter UI
function travelingCompanionDistanceMeter:showTheUI()
    local scale = self.state.uiScale;

    if scale < 0 then
        return; -- Do not draw if we don't know the scale
    end

    ImGui.SetNextWindowPos(50, 50, ImGuiCond.FirstUseEver);
    ImGui.SetNextWindowSize(380*scale, 125*scale, ImGuiCond.Appearing);
    ImGui.PushStyleColor(ImGuiCol.Text, 0xFF00DDFF); -- 0xAABBGGRR
    ImGui.PushStyleColor(ImGuiCol.WindowBg, 0x99000000);
    ImGui.PushStyleColor(ImGuiCol.Border, 0x00000000);        
	
    if ImGui.Begin("TCDM") then
        ImGui.SetWindowFontScale(1.15);
        ImGui.Text("Traveled: " .. string.format(
            "%.5f", self.output.distanceTraveled) .. " m\n"
            .. string.format("Speed: % 5.0f km/h; top=%.2f km/h\n", self.output.displayedSpeed, self.output.topSpeed)
            .. string.format("x=%.2f y=%.2f z=%.2f t=%.3f\n", self.lastPos.x, self.lastPos.y, self.lastPos.z, self.lastPos.timeTick)
            .. string.format("accel= % 4.2f G (max=%.2f G)", self.output.displayedAccel, self.output.accelMax)
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
    self.speedPoints.speedReady = false;

    self.output.distanceTraveled = 0;
    self.output.speed = 0;
    self.output.topSpeed = 0;
    self.output.displayedSpeed = 0;
    self.output.displayedSpeedTime = -1;

    -- Acceleration
    self.output.accel = {0, 0, -1};
    self.output.accelint = 1;
    self.output.displayedAccel = 1;
    self.output.displayedAccelTime = -1;
    self.output.accelMax = 1;

    self.state.frameCounter = 0;
    if(alsoResetDisplayedState) then
        self.state.displayed = false; -- The companion isn't displayed by default
    end

    self:refreshUIScale(); -- Determine self.state.uiScale

    self.lastPos.timeTick = -1.0;
    self.lastPos.x = 0;
    self.lastPos.y = 0;
    self.lastPos.z = 0;

    -- Speed points
    self.speedPoints.speedPos = 0;
    self.speedPoints.speedSize = 25;
    self.speedPoints.speedVals = {};
    self.speedPoints.totalLength = 0;
    self.speedPoints.totalTime = 0;
    for i=1,self.speedPoints.speedSize do
        self.speedPoints.speedVals[i] = {
            0, -- x
            0, -- y
            0, -- z
            0, -- t
            0, -- l (path length)
            0, -- v(speed)
            {  -- acceleration info
                {0, 0, 0}, -- movement vector across all data points, m
                0,         -- time diff for the movement vector, s
                {0, 0, 0}, -- current acceleration vector, 3x m/s^2
                0,         -- current acceleration intensity, m/s^2
            },
        };
    end
end

-- Produce and return the object for CET to work with
return travelingCompanionDistanceMeter:new();