function [Z_Bus, Y_Bus] = zbus_formation(file_path)
    %--------------------------------------------------------------------------
    % This Section Reads the Data and Converts It to Desired Format 
    %--------------------------------------------------------------------------
    %% Reading Data From txt
    fileID = fopen(file_path, 'r');
    fileContent = textscan(fileID, '%s', 'Delimiter', '\n');
    fclose(fileID);
    lines = fileContent{1};
    
    %Recording Relevant Bus Data
    for i = 1:length(lines)
        if strcmp(lines{i}(1:16), 'BUS DATA FOLLOWS') 
            bus_data_raw = {};
            for j = (i+1):length(lines)
                if strcmp(lines{j}(1:4),'-999')     
                    break
                else
                bus_data_raw = vertcat(bus_data_raw, lines{j});
                end
            end
            break
        end
    end
    
    %Recording Relevant Branch Data
    for i = (j+1):length(lines)
        if strcmp(lines{i}(1:19), 'BRANCH DATA FOLLOWS')  
            branch_data_raw = {};
            for j = (i+1):length(lines)
                if strcmp(lines{j}(1:4),'-999')     
                    break
                else
                    branch_data_raw = vertcat(branch_data_raw, lines{j});
                end
            end
            break
        end
    end
    
    %% Modifying the Data
    
    % Creating the Bus Data Matrix
    bus_data_matrix = zeros(length(bus_data_raw),3);    
    for i = 1:length(bus_data_raw)
        splitted_string = strsplit(bus_data_raw{i}(15:end));
        bus_data_matrix(i,1) = i;                                   % Bus Number
        bus_data_matrix(i,2) = str2double(splitted_string(15));     % Shunt conductance G (per unit)
        bus_data_matrix(i,3) = str2double(splitted_string(16));     % Shunt susceptance B (per unit)
    end
    
    % Creating the Branch Data Matrix
    branch_data_matrix = zeros(length(branch_data_raw),7);    
    for i = 1:size(branch_data_matrix, 1)
        splitted_string = strsplit(branch_data_raw{i});
        branch_data_matrix(i,1) = str2double(splitted_string(1));      % Tap bus number
        branch_data_matrix(i,2) = str2double(splitted_string(2));      % Z bus number
        branch_data_matrix(i,3) = str2double(splitted_string(6));      % Type (0 = Transmission Line, 1 = Transformer)
        branch_data_matrix(i,4) = str2double(splitted_string(7));      % Branch resistance R, per unit
        branch_data_matrix(i,5) = str2double(splitted_string(8));      % Branch reactance X
        branch_data_matrix(i,6) = str2double(splitted_string(9));      % Line charging B, per unit
        branch_data_matrix(i,7) = str2double(splitted_string(15));     % Transformer final turns ratio
    end
    
    % Adding Line Charging Affects to Bus Data Matrix
    for i = 1:size(branch_data_matrix, 1)
        if branch_data_matrix(i,6) ~= 0
            shunt_charging_capacitance = branch_data_matrix(i,6) / 2;
            new_line_charging_capacitance_1 = [branch_data_matrix(i,1) 0 shunt_charging_capacitance];
            new_line_charging_capacitance_2 = [branch_data_matrix(i,2) 0 shunt_charging_capacitance];
            bus_data_matrix = vertcat(bus_data_matrix, new_line_charging_capacitance_1);
            bus_data_matrix = vertcat(bus_data_matrix, new_line_charging_capacitance_2);
        end
    end
    
    % Adding Tap Transformer Affects to Bus Data Matrix
    for i = 1:size(branch_data_matrix, 1)
        if branch_data_matrix(i,3) == 1
            a = branch_data_matrix(i,7);
            shunt_admittance_tap = ( (1-a) / (a*a) ) * ( 1 / complex(branch_data_matrix(i,4),branch_data_matrix(i,5)) );
            shunt_admittance_nontap = ( (a-1) / a) * ( 1 / complex(branch_data_matrix(i,4),branch_data_matrix(i,5)) );
            new_line_tap = [branch_data_matrix(i,1) real(shunt_admittance_tap) imag(shunt_admittance_tap)];
            new_line_nontap = [branch_data_matrix(i,2) real(shunt_admittance_nontap) imag(shunt_admittance_nontap)];
            bus_data_matrix = vertcat(bus_data_matrix,new_line_tap);
            bus_data_matrix = vertcat(bus_data_matrix,new_line_nontap);
        end
    end
    
    % Adding the Shunts Connected to the Same Bus in Bus Data Matrix
    for i = 1:length(bus_data_matrix)
        for j = (i+1):length(bus_data_matrix)
            if bus_data_matrix(i,1) == bus_data_matrix(j,1) 
                bus_data_matrix(i,2) = bus_data_matrix(i,2) + bus_data_matrix(j,2);
                bus_data_matrix(i,3) = bus_data_matrix(i,3) + bus_data_matrix(j,3);
            end
        end
    end    
    bus_data_matrix = bus_data_matrix(1:length(bus_data_raw), :);
    
    % Converting Admittances to Impedances in Bus Data Matrix
    for i = 1:length(bus_data_matrix)
        G = bus_data_matrix(i,2);
        B = bus_data_matrix(i,3);
        Z = 1/complex(G,B);
        bus_data_matrix(i,2) = real(Z);
        bus_data_matrix(i,3) = imag(Z);
    end
    
    %Adding Tap Transformer Affects to Branch Data Matrix
    for i = 1:size(branch_data_matrix, 1)
        if branch_data_matrix(i,3) == 1
            branch_data_matrix(i,5) = branch_data_matrix(i,5)*branch_data_matrix(i,7);
            branch_data_matrix(i,4) = branch_data_matrix(i,4)*branch_data_matrix(i,7);
        end
    end
    
    % Deleting Unnecessary Columns
    branch_data_matrix(:,7) = [];
    branch_data_matrix(:,6) = [];
    branch_data_matrix(:,3) = [];
    
    % Sorting Branch Data Matrix for Better Implementation
    for i = 1:size(branch_data_matrix,1)
        if branch_data_matrix(i,1) > branch_data_matrix(i,2)
            cl1 = branch_data_matrix(i,1);
            cl2 = branch_data_matrix(i,2);
            branch_data_matrix(i,1) = cl2;
            branch_data_matrix(i,2) = cl1;
        end
    end
    branch_data_matrix = sortrows(branch_data_matrix);

    %% Building Zbus    

        Z_Bus = zeros(size(bus_data_matrix,1));
    % Adding Bus Data Matrix (Shunt Variables) to Zbus    
    for i = 1:size(bus_data_matrix, 1)
        Z_Bus(i,i) = complex(bus_data_matrix(i,2),bus_data_matrix(i,3));    
    end
    
    % Adding Branches Between Busses

    for i = 1:size(branch_data_matrix,1)
        from = branch_data_matrix(i,1);
        to = branch_data_matrix(i,2);
        Z = complex(branch_data_matrix(i,3),branch_data_matrix(i,4));
        matrix_size = length(Z_Bus);
        for j = 1:matrix_size
            Z_Bus(j,matrix_size+1) = Z_Bus(j,from) - Z_Bus(j,to);
            Z_Bus(matrix_size+1,j) = Z_Bus(j,matrix_size+1);                    
        end
        Z_Bus(matrix_size+1,matrix_size+1) = Z_Bus(from,from)...
            + Z_Bus(to,to) + Z - 2 * Z_Bus(from,to);  
        % Apply Kron Reduction 
        initial_size = length(Z_Bus);
        final_size = initial_size - 1;
        reducted_matrix = zeros(final_size);        
        for k = 1:final_size
            for l = 1:final_size
                reducted_matrix(k,l) = Z_Bus(k,l)...
                    - Z_Bus(k,initial_size)*Z_Bus(initial_size,l)/Z_Bus(initial_size,initial_size);
            end
        end
        Z_Bus = reducted_matrix;
    end

    
    %% Finding Y_Bus
    Y_Bus = inv(Z_Bus);
    % Eliminating Rounding Errors in Y_Bus
    Y_Bus(abs(Y_Bus) < 0.000001) = 0;

    % Plot of Sparsity Pattern of Y_Bus
    figure;
    spy(Y_Bus);
    xlabel('Column Index');
    ylabel('Row Index');
    title('Sparsity Pattern of Y Bus');
    set(gcf, 'Name', 'Sparsity Pattern of Y Bus');

end

