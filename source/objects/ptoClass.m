%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Copyright 2014 National Renewable Energy Laboratory and National 
% Technology & Engineering Solutions of Sandia, LLC (NTESS). 
% Under the terms of Contract DE-NA0003525 with NTESS, 
% the U.S. Government retains certain rights in this software.
% 
% Licensed under the Apache License, Version 2.0 (the "License");
% you may not use this file except in compliance with the License.
% You may obtain a copy of the License at
% 
% http://www.apache.org/licenses/LICENSE-2.0
% 
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS,
% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
% See the License for the specific language governing permissions and
% limitations under the License.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

classdef ptoClass<handle
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % The ``ptoClass`` creates a ``pto`` object saved to the MATLAB
    % workspace. The ``ptoClass`` includes properties and methods used
    % to define PTO connections between the body motion relative to the global reference 
    % frame or relative to other bodies. 
    %
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    properties (SetAccess = 'public', GetAccess = 'public')%input file 
        name                    = 'NOT DEFINED'                                 % (`string`) Specifies the pto name. For ptos this is defined by the user, Default = ``NOT DEFINED``. 
        k                       = 0                                             % (`float`) Linear PTO stiffness coefficient. Default = `0`.
        c                       = 0                                             % (`float`) Linear PTO damping coefficient. Default = `0`.
        equilibriumPosition     = 0                                             % (`float`) Linear PTO damping coefficient. Default = `0`.
        pretension              = 0                                             % (`float`) Linear PTO damping coefficient. Default = `0`.
        loc                     = [999 999 999]                                 % (`3x1 float vector`) PTO location [m]. Defined in the following format [x y z]. Default = ``[999 999 999]``.
        orientation             = struct(...                                    % 
                                         'z', [0, 0, 1], ...                    % 
                                         'y', [0, 1, 0], ...                    % 
                                         'x', [], ...                           % 
                                         'rotationMatrix',[])                   % Structure defining the orientation axis of the pto. ``z`` (`3x1 float vector`) defines the direciton of the Z-coordinate of the pto, Default = [``0 0 1``]. ``y`` (`3x1 float vector`) defines the direciton of the Y-coordinate of the pto, Default = [``0 1 0``]. ``x`` (`3x1 float vector`) internally calculated vector defining the direction of the X-coordinate for the pto, Default = ``[]``. ``rotationMatrix`` (`3x3 float matrix`) internally calculated rotation matrix to go from standard coordinate orientation to the pto coordinate orientation, Default = ``[]``.
        initDisp                = struct(...                                    % Structure defining the initial displacement
                                         'initLinDisp',          [0 0 0])       % Structure defining the initial displacement of the pto. ``initLinDisp`` (`3x1 float vector`) is defined as the initial displacement of the pto [m] in the following format [x y z], Default = [``0 0 0``].
    end 
    
    properties (SetAccess = 'public', GetAccess = 'public')%internal
        ptoNum                  = []                                            % PTO number.
    end
    
    methods                                                            
        function obj = ptoClass(name)                                  
            % This method initilizes the ``ptoClass`` and creates a
            % ``pto`` object.          
            %
            % Parameters
            % ------------
            %     filename : string
            %         String specifying the name of the pto
            %
            % Returns
            % ------------
            %     pto : obj
            %         ptoClass object         
            %
             obj.name = name;
        end
        
        function obj = checkLoc(obj,action)               
            % This method checks WEC-Sim user inputs and generate an error message if the constraint location is not defined in constraintClass.
            
            % Checks if location is set and outputs a warning or error. Used in mask Initialization.
            switch action
              case 'W'
                if obj.loc == 999 % Because "Allow library block to modify its content" is selected in block's mask initialization, this command runs twice, but warnings cannot be displayed during the first initialization. 
                    obj.loc = [888 888 888];
                elseif obj.loc == 888
                    obj.loc = [0 0 0];
                    s1= ['For ' obj.name ': pto.loc was changed from [999 999 999] to [0 0 0].'];
                    warning(s1)
                end
              case 'E'
                  try
                      if obj.loc == 999
                        s1 = ['For ' obj.name ': pto(#).loc needs to be specified in the WEC-Sim input file.'...
                          ' pto.loc is the [x y z] location, in meters, for the rotational PTO.'];
                        error(s1)
                      end
                  catch exception
                      throwAsCaller(exception)
                  end
            end
        end
        
        function obj = setOrientation(obj)
            % This method calculates the constraint ``x`` vector and ``rotationMatrix`` matrix in the ``orientation`` structure based on user input.
            obj.orientation.z = obj.orientation.z / norm(obj.orientation.z);
            obj.orientation.y = obj.orientation.y / norm(obj.orientation.y);
            z = obj.orientation.z;
            y = obj.orientation.y;
            if abs(dot(y,z))>0.001
                error('The Y and Z vectors defining the constraint''s orientation must be orthogonal.')
            end
            x = cross(y,z)/norm(cross(y,z));
            x = x(:)';
            obj.orientation.x = x;
            obj.orientation.rotationMatrix  = [x',y',z'];
        end

        
        function obj = setPretension(obj)
            % This method calculates the equilibrium position in the joint to provide pretension, which is activated when the pretension value is not equal to zero and equilibrium position is not over written.
            if obj.equilibriumPosition == 0
                if obj.pretension ~= 0
                    obj.equilibriumPosition = -obj.pretension./obj.k;
                end
            end
        end


        function setInitDisp(obj, x_rot, ax_rot, ang_rot, addLinDisp)
            % This method sets initial displacement while considering an initial rotation orientation. 
            %
            %``x_rot`` (`3x1 float vector`) is rotation point [m] in the following format [x y z], Default = ``[]``.
            % 
            %``ax_rot`` (`3x1 float vector`) is the axis about which to rotate to constraint and must be a normal vector, Default = ``[]``.
            %
            %``ang_rot`` (`float`) is the rotation angle [rad], Default = ``[]``.
            %
            %``addLinDisp`` ('float') is the initial linear displacement [m] in addition to the displacement caused by the pto rotation, Default = '[]'.
            loc = obj.loc;
            relCoord = loc - x_rot;
            rotatedRelCoord = obj.rotateXYZ(relCoord,ax_rot,ang_rot);
            newCoord = rotatedRelCoord + x_rot;
            linDisp = newCoord-loc;
            obj.initDisp.initLinDisp= linDisp + addLinDisp; 
        end

        function xn = rotateXYZ(obj,x,ax,t)
            %This method rotates a point about an arbitrary axis.
            %
            %``x`` (`3x1 float vector`) is the point coordiantes.
            %
            %``ax`` (`3x1 float vector`) is the axis about which to rotate the pto and must be a normal vector.
            %
            %``t``  (`float`) is the rotation angle of the pto.
            % 
            %``xn`` (`3x1 float vector`) is the new point coordiantes after rotation.
            rotMat = zeros(3);
            rotMat(1,1) = ax(1)*ax(1)*(1-cos(t))    + cos(t);
            rotMat(1,2) = ax(2)*ax(1)*(1-cos(t))    + ax(3)*sin(t);
            rotMat(1,3) = ax(3)*ax(1)*(1-cos(t))    - ax(2)*sin(t);
            rotMat(2,1) = ax(1)*ax(2)*(1-cos(t))    - ax(3)*sin(t);
            rotMat(2,2) = ax(2)*ax(2)*(1-cos(t))    + cos(t);
            rotMat(2,3) = ax(3)*ax(2)*(1-cos(t))    + ax(1)*sin(t);
            rotMat(3,1) = ax(1)*ax(3)*(1-cos(t))    + ax(2)*sin(t);
            rotMat(3,2) = ax(2)*ax(3)*(1-cos(t))    - ax(1)*sin(t);
            rotMat(3,3) = ax(3)*ax(3)*(1-cos(t))    + cos(t);
            xn = x*rotMat;
        end

        function listInfo(obj)                                         
            % This method prints pto information to the MATLAB Command Window.
            fprintf('\n\t***** PTO Name: %s *****\n',obj.name)
            fprintf('\tPTO Stiffness           (N/m;Nm/rad) = %G\n',obj.k)
            fprintf('\tPTO Damping           (Ns/m;Nsm/rad) = %G\n',obj.c)
        end
    end    
end