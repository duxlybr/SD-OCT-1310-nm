function idx = orderBidirectionalAngles(scanAxisCount)
%ORDERBIDIRECTIONALANGLES Preserve maintained left/right angular ordering.

    Jumps1 = repmat([3 1], 1, scanAxisCount);
    Jumps1 = Jumps1(1:scanAxisCount-1);
    Jumps2 = repmat([1 3], 1, scanAxisCount);
    Jumps2 = Jumps2(1:scanAxisCount-1);
    idx1 = cumsum([1, Jumps1]);
    idx2 = cumsum([2, Jumps2]);
    idx = [idx1 idx2];
end
