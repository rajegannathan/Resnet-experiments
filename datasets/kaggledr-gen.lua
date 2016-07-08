local KaggleDR = require('datasets/kaggledr')

M = {}

local _DR_LEVELS = {0, 1, 2, 3, 4}

local function _pruneData(allData, percentage)
    local dataSize = 0
    for dr_level = 0,4 do
        local size = allData[dr_level]:size(1)
        local perm = torch.randperm(size):long()
        local targetSize = math.ceil(size * percentage/100)
        local indices = torch.linspace(1, targetSize, targetSize):long()

        dataSize = dataSize + targetSize

        allData[dr_level] = allData[dr_level]:index(1, perm) -- shuffle the dataSet
        allData[dr_level] = allData[dr_level]:index(1, indices)
    end

    return allData, dataSize;
end

local function _train_validation_split(imageLabels, valPercent)
    local validationSet = {}
    local trainingSet = {}
    local trainingSize = 0
    local validationSize = 0
    local totalSize  = 0
    for dr_level = 0,4 do
        local size = imageLabels[dr_level]:size(1)
        local perm = torch.randperm(size):long()
        local targetSize = math.ceil(size * valPercent/100)
        local indices = torch.linspace(1, targetSize, targetSize):long()

        totalSize = totalSize + size
        validationSize = validationSize + targetSize

        imageLabels[dr_level] = imageLabels[dr_level]:index(1, perm) -- shuffle the dataSet
        validationSet[dr_level] = imageLabels[dr_level]:index(1, indices)

        local trainIndices = torch.linspace(targetSize + 1, size, size - targetSize):long()
        trainingSet[dr_level] = imageLabels[dr_level]:index(1, trainIndices)
    end

    trainingSize = totalSize - validationSize

    return trainingSet, trainingSize, validationSet, validationSize
end

local function flatten(classToImages, size)
    local result = torch.Tensor(size, 3)
    local startP = 1
    local size = 0 
    for i, v in ipairs(_DR_LEVELS) do
        size = classToImages[v]:size(1)
        result[{{startP, startP + size - 1}}] = classToImages[v]
        startP = startP + size 
    end
    return result
end

local function _saveLabelFile(split, labelFile, headers, opt)

    local skip = headers or true
    local count = 1

    local COLS = 0
    local ROWS = 0

    for line in io.lines(labelFile) do
        if ROWS == 0 then
            COLS = #line:split(',') + 1 -- adding one for left/right eye position
        end
        ROWS = ROWS + 1
    end
    if headers then
        ROWS = ROWS - 1
    end

    local imageLabels = torch.DoubleTensor(ROWS,COLS)

    for line in io.lines(labelFile) do
        if not skip then
            local image, pos, dr_level = line:match("(%d*)_(%a*),(%d*)")

            pos_int = 2
            if pos == "left" then
                pos_int = 1
            end

            imageLabels[count][1] = image
            imageLabels[count][2] = pos_int
            imageLabels[count][3] = dr_level
            count = count + 1
        end
        skip = false
    end

    local perm = torch.randperm(imageLabels:size(1))
    imageLabels = imageLabels:index(1, perm:long())
    
    local indices = torch.linspace(1, imageLabels:size(1), imageLabels:size(1)):long()
    local classToImages = {}
    local dataSize = 0
    local info = {}

    for i = 0,4 do
        local selected = indices[imageLabels[{{}, {3}}]:eq(i)]
        classToImages[i] = imageLabels:index(1,selected)
    end

    if opt.dataP > 0 and opt.dataP < 100 and opt.dataP%1 == 0 then
        classToImages, dataSize = _pruneData(classToImages, opt.dataP)
    end

    if split=="train" and opt.val > 0 and opt.val < 100 and opt.val % 1 == 0 then
        classToImages, dataSize, validationImages, valSize = _train_validation_split(classToImages, opt.val)
        info['val'] = {}
        info.val['classToImages'] = validationImages 
        info.val['size'] = valSize
        info.val['data'] = flatten(validationImages, valSize)
    end

    info[split] = {}
    info[split]['classToImages'] = classToImages
    info[split]['size'] = dataSize
    info[split]['data'] = flatten(classToImages, dataSize)

    -- local fileName = table.concat({"processed", "train", opt.dataP, opt.val, "t7"}, '.');
    -- torch.save(fileName, classToImages)
    return info 
end

function M.exec(opt, setName)
    local labelFile = opt[setName..'L']

    assert(paths.dirp(opt.data), 'data folder is not valid'..opt.data)
    assert(paths.filep(labelFile), 'opt.'..setName..'L is not valid'..labelFile)

    local dataSetInfo = _saveLabelFile(setName, labelFile, true, opt)

    local dataSets = {}

    for split, info in pairs(dataSetInfo) do
        table.insert(dataSets, KaggleDR(opt, split, info))
    end

    return dataSets
end


return M