class M:
    def __init__(self, moteid, children=None):
        self.moteid = moteid
        self.children = children or []
        
        self.parent = None
        
        self.listen = None
        self.listen_ack = None
        self.send = None
        self.send_done = None
        self.send_ack = None
    
    def num_total_children(self):
        return sum([mote.num_total_children()+1 for mote in self.children])
        
    def add_child(self, child):
        self.children.append(child)
        
    def parentize(self):
        print(self.moteid)
        self.parent = self
        for mote in self.children:
            mote.parentize()
            mote.parent = self
    
    def calculate(self, offset):
        for mote in self.children:
            offset = mote.calculate(offset)
        
        if len(self.children) > 0:
            self.listen = offset
            
            # find out how many send slots are needed based on how many children they have.
            for idx, mote in enumerate(self.children):
                mote.send = offset
                
                slots_needed = 1 + mote.num_total_children()
                mote.send_done = mote.send + slots_needed
                
                offset += slots_needed
            
            # after send times have been determined, set a common ack time
            self.listen_ack = offset
            for mote in self.children:
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
            elif self.send is not None and i >= self.send and i < self.send_done:
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
    
    def generate(self):
        params = {
            'device_id': self.moteid,
            'sendto': self.parent.moteid,
            'listen': self.listen or 0,
            'listen_ack': self.listen_ack or 0,
            'send': self.send or 0,
            'send_ack': self.send_ack or 0,
            'send_done': self.send_done or 0
        }
        
        #return "{{ .device_id = {device_id:>3}, .period = {period:>5}, .slotsize = {slotsize:>3}, .listen = {listen:>3}, .listen_ack = {listen_ack:>3}, .send = {send:>3}, .send_ack = {send_ack:>3} }},".format(**params)
        #return "    case {device_id}: return (schedule_t){{ .device_id = {device_id:>3}, .period = {period:>5}, .slotsize = {slotsize:>3}, .listen = {listen:>3}, .listen_ack = {listen_ack:>3}, .send = {send:>3}, .send_ack = {send_ack:>3} }},".format(**params)
        return "      case {device_id:>2}: {{ mySchedule.device_id = {device_id:>3}; mySchedule.sendto = {sendto:>3}; mySchedule.listen = {listen:>3}; mySchedule.listen_ack = {listen_ack:>3}; mySchedule.send = {send:>3}; mySchedule.send_done = {send_done:>3}; mySchedule.send_ack = {send_ack:>3}; }} break;".format(**params)
    
    def generate_all(self):
        lines = []
        for mote in self.children:
            lines.extend(mote.generate_all())
        lines.append(self.generate())
        return lines

base = [1, 2, 3, 4, 6, 8, 15, 16, 22, 28, 31, 32, 33]

mote28 = M(28, [M(6), M(16), M(22)])
mote15 = M(15, [M(31), M(32)])
mote3 = M(3, [mote28, M(33)])

sink = M(1, [mote3, M(2), M(4), M(8), mote15])

print("mote28", mote28.num_total_children())
print("mote3", mote3.num_total_children())
print("sink", sink.num_total_children())

sink.parentize()
length = sink.calculate(1)
print('\n'.join(sink.dump_all(length)))
print('\n'.join(sink.generate_all()))

