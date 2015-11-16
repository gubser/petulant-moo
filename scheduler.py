class M:
    def __init__(self, moteid, children=None):
        self.moteid = moteid
        self.children = children or []
        
        self.listen = None
        self.listen_ack = None
        self.send = None
        self.send_ack = None
        
    def add_child(self, child):
        self.children.append(child)
    
    def calculate(self, offset):
        for mote in self.children:
            offset = mote.calculate(offset)
        
        if len(self.children) > 0:
            self.listen = offset
            self.listen_ack = offset + len(self.children)
        
            for idx, mote in enumerate(self.children):
                mote.send = offset + idx
                mote.send_ack = self.listen_ack
        
            return self.listen_ack+1
        
        return offset
    
    def dump(self, length):
        assert(self.listen is None or self.listen <= self.listen_ack)
        assert(self.send is None or self.listen_ack is None or self.listen_ack <= self.send)
        assert(self.send is None or self.send <= self.send_ack)
        
        s = "{:03d}: ".format(self.moteid)
        for i in range(length):
            if self.listen is not None and i >= self.listen and i < self.listen_ack:
                s += "L"
            elif self.listen_ack is not None and i == self.listen_ack:
                s += "l"
            elif self.send is not None and i == self.send:
                s += "S"
            elif self.send_ack is not None and i == self.send_ack:
                s += "s"
            else:
                s += " "
        return s
    
    def dump_all(self, length):
        lines = []
        for mote in self.children:
            lines.extend(mote.dump_all(length))
            
        lines.append(self.dump(length))
        return lines
    
    def generate(self, period, slotsize):
        params = {
            'device_id': self.moteid,
            'period': period,
            'slotsize': slotsize,
            'listen': self.listen or 0,
            'listen_ack': self.listen_ack or 0,
            'send': self.send or 0,
            'send_ack': self.send_ack or 0
        }
        
        #return "{{ .device_id = {device_id:>3}, .period = {period:>5}, .slotsize = {slotsize:>3}, .listen = {listen:>3}, .listen_ack = {listen_ack:>3}, .send = {send:>3}, .send_ack = {send_ack:>3} }},".format(**params)
        return "    case {device_id}: return (schedule_t){{ .device_id = {device_id:>3}, .period = {period:>5}, .slotsize = {slotsize:>3}, .listen = {listen:>3}, .listen_ack = {listen_ack:>3}, .send = {send:>3}, .send_ack = {send_ack:>3} }},".format(**params)
    
    def generate_all(self, period, slotsize):
        lines = []
        for mote in self.children:
            lines.extend(mote.generate_all(period, slotsize))
        lines.append(self.generate(period, slotsize))
        return lines


PERIOD = 1000
SLOTSIZE = 10

base = [1, 2, 3, 4, 6, 8, 15, 16, 22, 28, 31, 32, 33]

mote28 = M(28, [M(6), M(16), M(22), M(18)])

mote33 = M(33, [mote28, M(3), M(32), M(31)])

sink = M(1, [mote33, M(2), M(4), M(8), M(15)])

length = sink.calculate(0)
print('\n'.join(sink.dump_all(length)))
print('\n'.join(sink.generate_all(PERIOD, SLOTSIZE)))


"""

motes = {
    2:None,
    4:None,
    8:None,
    15:None,
    33: {
        3: None,
        32: None,
        31: None
        28: {
            6:None,
            16:None,
            22:None,
            18:None
        }
    }
}


"""
