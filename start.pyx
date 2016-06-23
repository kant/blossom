import numpy as np
import matplotlib.pyplot as plt


from libc.stdlib cimport malloc, free


cdef enum:
    TAG_WORK = 1
    TAG_BLOSSOM = 2
    TAG_OUTER = 4
    TAG_INNER = 8
    TAG_DOUBLE = 16

cdef:
    struct node:
        int index

        int y

        edge *pair

        int n_edges
        edge **edge_list

        edge *cycle_start

        int n_restore
        node **restore_list

    struct edge:
        int index

        int slack
        
        node *node_plus
        node *node_minus

        edge *parent

        edge *cycle
        int tag
    struct instruction:
        int delta
        int tag
        edge *edge

cdef void swap_nodes(edge *e):
    cdef node *t
    t = e.node_plus
    e.node_plus = e.node_minus
    e.node_minus = t

cdef class Graph:


    cdef node *nodes
    cdef public int len_nodes

    cdef edge *edges
    cdef public int len_edges

    cdef edge **incidence
    cdef public int len_incidence

    cdef node **restore 
    cdef public int len_restore

    cdef float *pos_x
    cdef float *pos_y

    cdef edge root

    cdef int len_instructions
    cdef instruction *instructions
    cdef int len_seen_edges
    cdef edge **seen_edges

    cdef public int size, max_neighbors

    def __init__(self, size=256, max_neighbors=10):

        self.size = size
        self.max_neighbors = max_neighbors

        self.nodes = <node*> malloc(size*sizeof(node))
        self.edges = <edge*> malloc(size*sizeof(edge))
        self.incidence = <edge**> malloc(size*max_neighbors*sizeof(edge*))
        self.restore = <node**> malloc(size*sizeof(node*))
        self.instructions = <instruction*> malloc(size*sizeof(instruction))
        self.seen_edges = <edge**> malloc(size*sizeof(edge*))

        self.pos_x = <float*> malloc(size*sizeof(float))
        self.pos_y = <float*> malloc(size*sizeof(float))

        self.len_nodes = 0
        self.len_edges = 0
        self.len_incidence = 0
        self.len_restore = 0
        self.len_instructions = 0
        self.len_seen_edges = 0

        self.root.node_plus = NULL
        self.root.node_minus = NULL
        self.root.parent = &self.root
        self.root.index = -2

    def add_vertex(self, x, y):
        cdef int index
        cdef node *n
        cdef node *n2
        cdef edge *e

        index = self.len_nodes
        self.len_nodes += 1
        
        n = &self.nodes[index]

        n.index = index
        n.y = 0

        n.pair = NULL

        n.n_edges = 0
        n.edge_list = &self.incidence[self.len_incidence]
        self.len_incidence += self.max_neighbors
        
        n.n_restore = 0
        n.restore_list = NULL
        self.pos_x[index] = x
        self.pos_y[index] = y

        return index

    def add_edge(self, index1, index2):
        cdef node *n1
        cdef node *n2
        cdef edge *e

        assert index1 < self.len_nodes
        assert index2 < self.len_nodes

        n1 = &self.nodes[index1]
        n2 = &self.nodes[index2]

        e = &self.edges[self.len_edges]
        e.index = self.len_edges
        self.len_edges += 1

        e.slack = 0

        e.tag = 0

        e.node_plus = n1
        e.node_minus = n2

        e.parent = NULL
        e.cycle = NULL

        n1.edge_list[n1.n_edges] = e
        n1.n_edges += 1

        n2.edge_list[n2.n_edges] = e
        n2.n_edges += 1

        return e.index

    def show(self):
        cdef int i, j
        cdef node *n
        cdef edge *e

        print("Vertices:")

        for i in range(self.len_nodes):
            n = &self.nodes[i]
            print("%d (x=%g, y=%g):\n"%(n.index, self.pos_x[n.index], self.pos_y[n.index]))
            if n.pair != NULL and n.pair != <edge*> -1:
                print("pair: %d"%n.pair.index)
            for j in range(n.n_edges):
                print("   (%d, %d -- %d)"%
                    (n.edge_list[j].index,
                     n.edge_list[j].node_plus.index,
                     n.edge_list[j].node_minus.index))


        print("Edges:")
        for i in range(self.len_edges):
            e = &self.edges[i]
            print("(%d, %d -- %d) pnt=%d cyc=%d tags=%x"%
                (e.index,
                 e.node_plus.index,
                 e.node_minus.index,
                 -1 if e.parent == NULL else e.parent.index,
                 -1 if e.cycle == NULL else e.cycle.index,
                e.tag))

    def plot(self, ax=None):
        cdef edge *e
        if ax is None:
            ax = plt.gca()

        cdef int i

        xs = []
        ys = []
        cs = []

        for i in range(self.len_nodes):
            plt.text(self.pos_x[self.nodes[i].index],
                self.pos_y[self.nodes[i].index],
                "%d"%self.nodes[i].index)
            xs.append(self.pos_x[self.nodes[i].index])
            ys.append(self.pos_y[self.nodes[i].index])

            cs.append("blue" if self.nodes[i].restore_list == NULL else "green")

        plt.scatter(xs, ys, s=50, c=cs)


        if <node*>self.root.node_plus != NULL:
            x = self.pos_x[self.root.node_plus.index]
            y = self.pos_y[self.root.node_plus.index]
            plt.scatter((x), (y), s=150, c="red")

        for i in range(self.len_edges):
            e = &self.edges[i]
            xs = [self.pos_x[e.node_minus.index],
                    self.pos_x[e.node_plus.index]]
            ys = [self.pos_y[e.node_minus.index],
                    self.pos_y[e.node_plus.index]]


            x = e.node_plus.pair == e

            if e.cycle != NULL:
                color = "green"
                lw = 1
            else:
                if e.parent != NULL and x:
                    color = "purple"
                    lw = 3
                if e.parent == NULL and x:
                    color = "red"
                    lw = 3
                if e.parent != NULL and not x:
                    color = "blue"
                    lw = 1
                if e.parent == NULL and not x:
                    color = "black"
                    lw = 1

            plt.plot(xs, ys, "-", lw=lw, color=color)

    def check_all(self):
        self.check_graph_integrity()
        self.check_pairing()
        self.check_tree_integrity()
        self.check_tags()
        self.check_seen_edges()
        pass

    def check_graph_integrity(self):
        "For all edges, check whether the nodes declared as node_plus and node_minus have edge listed as incident"
        cdef edge *e
        cdef edge *e2

        for ei in range(self.len_edges):
            e = &self.edges[ei]
            for ei2 in range(e.node_plus.n_edges):
                if e.node_plus.edge_list[ei2] == e:
                    e2 = e.node_plus.edge_list[ei2]
                    break
                if e.node_minus.edge_list[ei2] == e:
                    e2 = e.node_minus.edge_list[ei2]
                    break
            assert e2 == e
            for ei2 in range(e.node_minus.n_edges):
                if e.node_minus.edge_list[ei2] == e:
                    e2 = e.node_minus.edge_list[ei2]
                    break
                if e.node_minus.edge_list[ei2] == e:
                    e2 = e.node_minus.edge_list[ei2]
                    break
            assert e2 == e

    def check_pairing(self):
        "For all edges, check that the node is declared as pairing by both or none of the vertices"
        cdef edge *e
        for ei in range(self.len_edges):
            e = &self.edges[ei]
            if e.node_plus.pair == e:
                assert e.node_minus.pair == e
            if e.node_minus.pair == e:
                assert e.node_plus.pair == e
    
    def check_tree_integrity(self):
        "Check if there is only one alternating tree"
        cdef edge* e
        cdef edge* ep

        assert self.root.parent == &self.root

        for i in range(self.len_edges):
            e = &self.edges[i]

            if e.parent != NULL and e.cycle == NULL:
                # apparently in tree, runs down to root?
                ep = e
                while ep.parent != ep and ep.parent != NULL:
                    ep = ep.parent

                assert ep == &self.root

                ep = e.parent
                if e.node_plus.pair == e:
                    # alternating property
                    assert ep.node_plus.pair != ep
                    assert e.node_minus == ep.node_minus
                if e.node_plus.pair != e:
                    # alternating property
                    assert e.node_plus == ep.node_plus
                    if ep != &self.root:
                        assert ep.node_plus.pair == ep
                        assert ep.parent != NULL
                    # unpaired edges cannot be leaves
                    assert e.node_minus.pair != NULL
                    assert e.node_minus.pair.parent == e

    def check_tags(self):
        "check if the tags of all the edges are correct"
        cdef edge* e

        cdef int plus_out_in_tree, plus_inn_in_tree, minus_inn_in_tree, minus_out_in_tree

        for i in range(self.len_edges):
            e = &self.edges[i]

            if not e.tag & TAG_BLOSSOM:

                plus_out_in_tree = (e.node_plus.pair != NULL 
                        and e.node_plus.pair != <edge*> -1 
                        and e.node_plus.pair.parent != NULL
                        and e.node_plus.pair.node_plus == e.node_plus)
                plus_inn_in_tree = (e.node_plus.pair != NULL 
                        and e.node_plus.pair != <edge*> -1 
                        and e.node_plus.pair.parent != NULL
                        and e.node_plus.pair.node_minus == e.node_plus)
                minus_inn_in_tree = (e.node_minus.pair != NULL 
                        and e.node_minus.pair != <edge*> -1 
                        and e.node_minus.pair.parent != NULL
                        and e.node_minus.pair.node_minus == e.node_minus)
                minus_out_in_tree = (e.node_minus.pair != NULL 
                        and e.node_minus.pair != <edge*> -1 
                        and e.node_minus.pair.parent != NULL
                        and e.node_minus.pair.node_plus == e.node_minus)

                if e.tag & TAG_INNER:
                    assert minus_inn_in_tree

                if e.tag & TAG_OUTER: 
                    assert plus_out_in_tree

                if e.tag & TAG_INNER and e.tag & TAG_DOUBLE:
                    assert plus_inn_in_tree and minus_inn_in_tree

                if e.tag & TAG_OUTER and e.tag & TAG_DOUBLE:
                    assert plus_out_in_tree and minus_out_in_tree

            if e.tag & TAG_BLOSSOM:
                node_plus_in_blossom = (
                    e.node_plus.pair == <edge*> -1 
                    or (e.node_plus.pair != NULL
                        and e.node_plus.pair.cycle != NULL))
                node_minus_in_blossom = (
                    e.node_minus.pair == <edge*> -1 
                    or (e.node_minus.pair != NULL
                        and e.node_minus.pair.cycle != NULL))

                assert node_minus_in_blossom and node_minus_in_blossom

            if e.parent != NULL:
                assert e.tag & TAG_INNER and e.tag & TAG_OUTER

    def check_seen_edges(self):
        """Check whether all edges that have inner or outer tag set are in the seen list.
        The opposite need not be true, after expanding a blossom.
        """
        cdef edge *e, 
        for i in range(self.len_edges):
            e = &self.edges[i]

            if e.tag & TAG_INNER or e.tag & TAG_OUTER:
                for j in range(self.len_seen_edges):
                    if self.seen_edges[j] == e:
                        break
                else:
                    raise ValueError("tagged edge %d not in seen edge list")

    cdef void add_outer_edge(self, edge *e, node *node_in_tree):
        cdef instruction *ins

        if e.tag & TAG_OUTER:
            e.tag |= TAG_DOUBLE
        e.tag |= TAG_OUTER

        if e.node_plus != node_in_tree:
            swap_nodes(e)

        ins = &self.instructions[self.len_instructions]
        self.len_instructions += 1
        ins.tag = e.tag
        ins.edge = e

        self.seen_edges[self.len_seen_edges] = e
        self.len_seen_edges += 1

    cdef void add_inner_edge(self, edge *e, node *node_in_tree):
        if e.tag & TAG_INNER:
            e.tag |= TAG_DOUBLE
        e.tag |= TAG_INNER 
        if e.node_minus != node_in_tree:
            swap_nodes(e)

        self.seen_edges[self.len_seen_edges] = e
        self.len_seen_edges += 1

    def augment(self, edge_index):
        cdef edge *unpaired_e
        cdef edge *edge_in_tree

        assert edge_index < self.len_edges 



        unpaired_e = &self.edges[edge_index]

        assert unpaired_e.node_plus.pair != unpaired_e
        assert unpaired_e.node_minus.pair != unpaired_e


        if unpaired_e.node_plus.pair == NULL:
            swap_nodes(unpaired_e)

        assert unpaired_e.node_plus.pair != NULL
        assert unpaired_e.node_plus.pair.parent != NULL

        edge_in_tree = unpaired_e.node_plus.pair

        self._pair_edge(unpaired_e)

        while edge_in_tree.parent != edge_in_tree:
            self._pair_edge(edge_in_tree.parent)
            edge_in_tree = edge_in_tree.parent.parent

        for i in range(self.len_seen_edges):
            self.seen_edges[i].tag = 0
            self.seen_edges[i].parent = NULL

        self.len_seen_edges = 0
        self.len_instructions = 0

        self.root.node_plus = NULL

    def grow(self, edge_index):
        cdef edge *unpaired_e
        cdef edge *edge_in_tree
        cdef edge *new_paired_edge

        assert edge_index < self.len_edges

        unpaired_e = &self.edges[edge_index]

        assert unpaired_e.node_minus.pair != NULL 
        assert unpaired_e.node_plus.pair != NULL 


        if unpaired_e.node_minus.pair.parent != NULL:
            swap_nodes(unpaired_e)

        new_paired_edge = unpaired_e.node_minus.pair

        if new_paired_edge.node_plus == unpaired_e.node_minus:
            swap_nodes(new_paired_edge)


        unpaired_e.parent = unpaired_e.node_plus.pair
        new_paired_edge.parent = unpaired_e



        for i in range(new_paired_edge.node_plus.n_edges):
            self.add_outer_edge(new_paired_edge.node_plus.edge_list[i], 
                    new_paired_edge.node_plus)

        for i in range(new_paired_edge.node_minus.n_edges):
            self.add_inner_edge(new_paired_edge.node_minus.edge_list[i], 
                    new_paired_edge.node_minus)

    def shrink(self, edge_index):
        cdef edge *unpaired_e
        cdef node *blossom
        cdef edge *blossom_pair_parent
        cdef node *lonely_node
        cdef edge *e


        assert edge_index < self.len_edges
        unpaired_e = &self.edges[edge_index]

        assert unpaired_e.node_plus.pair != NULL 
        assert unpaired_e.node_plus.pair.parent != NULL
        assert unpaired_e.node_minus.pair != NULL 
        assert unpaired_e.node_minus.pair.parent != NULL

        
        blossom = &self.nodes[self.len_nodes]
        blossom.index = self.len_nodes
        self.len_nodes += 1

        blossom.n_edges = 0
        blossom.restore_list = &self.restore[self.len_restore]
        blossom.edge_list = &self.incidence[self.len_incidence]

        self.pos_x[blossom.index] = 0
        self.pos_y[blossom.index] = 0


        blossom.cycle_start = unpaired_e


        ### step 1: find the cycle:

        #leave breadcrumbs
        e = unpaired_e.node_plus.pair
        e.cycle = unpaired_e
        while e.parent != e:
            e.parent.cycle = e
            e = e.parent
        
        e = unpaired_e.node_minus.pair
        if e.cycle == NULL:
            while e.parent.cycle == NULL:
                e.cycle = e.parent
                e = e.parent

            e.cycle = e.parent.cycle
            unpaired_e.cycle = unpaired_e.node_minus.pair
            blossom.pair = e.parent
        else:
            blossom.pair = e
            unpaired_e.cycle = e.cycle


        blossom_pair_parent = blossom.pair.parent
        lonely_node = blossom.pair.node_plus


        #all edges in the blossom now point along the cycle with parent pointers

        ### step 2: collect the edges

        #run along the cycle once to mark the edges that should be added

    
        e = unpaired_e.cycle
        while e != unpaired_e:
            for i in range(e.node_plus.n_edges):
                e.node_plus.edge_list[i].tag += TAG_WORK # sets TAG_BLOSSOM if hit twice
            for i in range(e.node_minus.n_edges):
                e.node_minus.edge_list[i].tag += TAG_WORK
            e = e.cycle.cycle
        for i in range(e.node_plus.n_edges):
            e.node_plus.edge_list[i].tag += TAG_WORK

        #run a second time to add them to the edge and restore lists and change the node ends

        cnt = 1

        e = unpaired_e.cycle
        while e != unpaired_e:
            self.pos_x[blossom.index] += self.pos_x[e.node_plus.index]
            self.pos_y[blossom.index] += self.pos_y[e.node_plus.index]
            self.pos_x[blossom.index] += self.pos_x[e.node_minus.index]
            self.pos_y[blossom.index] += self.pos_y[e.node_minus.index]
            for i in range(e.node_plus.n_edges):
                if e.node_plus.edge_list[i].tag & 1 == 1:
                    self.incidence[self.len_incidence] = e.node_plus.edge_list[i]
                    self.len_incidence += 1
                    self.restore[self.len_restore] = e.node_plus
                    self.len_restore += 1
                    if e.node_plus.edge_list[i].node_plus == e.node_plus:
                        e.node_plus.edge_list[i].node_plus = blossom
                    else:
                        e.node_plus.edge_list[i].node_minus = blossom
                    blossom.n_edges += 1
                    e.node_plus.edge_list[i].tag &= ~TAG_WORK
                    #self.add_outer_edge(e.node_plus.edge_list[i], blossom)
                    #should not be necessary
                    if e.node_plus.edge_list[i].parent != NULL:
                        e.node_plus.edge_list[i].parent = blossom.pair

            for i in range(e.node_minus.n_edges):
                if e.node_minus.edge_list[i].tag & 1 == 1:
                    self.incidence[self.len_incidence] = e.node_minus.edge_list[i]
                    self.len_incidence += 1
                    self.restore[self.len_restore] = e.node_minus
                    self.len_restore += 1
                    if e.node_minus.edge_list[i].node_minus == e.node_minus:
                        e.node_minus.edge_list[i].node_minus = blossom
                    else:
                        e.node_minus.edge_list[i].node_plus = blossom
                    blossom.n_edges += 1
                    if e.node_minus.edge_list[i].tag & (TAG_INNER | TAG_DOUBLE) == TAG_INNER | TAG_DOUBLE:
                        e.node_minus.edge_list[i].tag &= ~TAG_DOUBLE
                    else:
                        e.node_minus.edge_list[i].tag &= ~TAG_INNER
                    self.add_outer_edge(e.node_minus.edge_list[i], blossom)
                    e.node_minus.edge_list[i].tag &= ~TAG_WORK


            cnt += 2
                
            e = e.cycle.cycle

        self.pos_x[blossom.index] += self.pos_x[e.node_plus.index]
        self.pos_y[blossom.index] += self.pos_y[e.node_plus.index]
        for i in range(e.node_plus.n_edges):
            if e.node_plus.edge_list[i].tag & 1 == 1:
                self.incidence[self.len_incidence] = e.node_plus.edge_list[i]
                self.len_incidence += 1
                self.restore[self.len_restore] = e.node_plus
                self.len_restore += 1
                if e.node_plus.edge_list[i].node_plus == e.node_plus:
                    e.node_plus.edge_list[i].node_plus = blossom
                else:
                    e.node_plus.edge_list[i].node_minus = blossom
                blossom.n_edges += 1
                e.node_plus.edge_list[i].tag &= ~TAG_WORK
                #self.add_outer_edge(e.node_plus.edge_list[i], blossom)
                if e.node_plus.edge_list[i].parent != NULL:
                    e.node_plus.edge_list[i].parent = blossom.pair


        blossom.pair.node_plus = blossom


        blossom.pair.parent = blossom_pair_parent
        lonely_node.pair = <edge*> -1



        self.pos_x[blossom.index] /= cnt
        self.pos_y[blossom.index] /= cnt

        #clean up cycle
        e = blossom.pair
        while e.parent != e:
            e.cycle = NULL
            e = e.parent
        e.cycle = NULL

    def expand(self, blossom_index):
        cdef node *blossom
        cdef edge *pair
        cdef edge *e
        cdef edge *start
        cdef edge *e2


        assert self.len_nodes > blossom_index

        blossom = &self.nodes[blossom_index]

        assert blossom.restore_list != NULL


        if blossom.pair.node_plus == blossom:
            swap_nodes(blossom.pair)


        # restore graph structure
        for i in range(blossom.n_edges):
            e = blossom.edge_list[i]
            if e.node_plus == blossom:
                e.node_plus = blossom.restore_list[i]
            else:
                e.node_minus = blossom.restore_list[i]
            if e.tag & (TAG_INNER | TAG_DOUBLE) == TAG_INNER | TAG_DOUBLE:
                e.tag &= ~TAG_DOUBLE
            else:
                e.tag &= ~TAG_INNER
            e.tag &= ~TAG_BLOSSOM

        # re-pair blossom if necessary
        if blossom.pair.node_minus.pair != <edge*> -1:
            start = blossom.pair.node_minus.pair.cycle

            if start.node_plus == blossom.pair.node_minus:
                start = start.cycle
            if start.node_minus == blossom.pair.node_minus:
                start = start.cycle

            e = start

            while e.cycle != start:
                self._pair_edge(e)
                e = e.cycle.cycle

        blossom.pair.node_minus.pair = blossom.pair

        # regrow the tree
        if blossom.pair.parent == NULL:
            pass
        else:
            e2 = blossom.pair.parent

            if (e2.node_minus.pair.cycle == NULL):
                #tree is not running through blossom, done
                pass

            elif (e2.node_minus.pair.cycle.node_minus == e2.node_minus or
                    e2.node_minus.pair.cycle.node_plus == e2.node_minus):
                # tree grows against cycle

                # run up to the pairing node
                e2 = e2.node_minus.pair
                start = e2
                
                while (e2.node_plus.pair != blossom.pair and
                        e2.node_minus.pair != blossom.pair):
                    e2 = e2.cycle

                e2 = e2.cycle
                e = blossom.pair.parent

                blossom.pair.parent = e2

                e2 = blossom.pair

                while e2 != start:

                    if e2.parent.node_minus != e2.node_minus:
                        swap_nodes(e2.parent)

                    for i in range(e2.node_minus.n_edges):
                        self.add_inner_edge(e2.node_minus.edge_list[i], e2.node_minus)
                    
                    e2 = e2.parent
                    #unpaired edge
                    e2.parent = e2.cycle

                    if e2.parent.node_minus != e2.node_minus:
                        swap_nodes(e2.parent)

                    for i in range(e2.node_plus.n_edges):
                        self.add_outer_edge(e2.node_plus.edge_list[i], e2.node_plus)

                    e2 = e2.parent
                    #paired edge

                    e2.parent = e2.cycle



                #final node and pairing
                e2.parent = e
                for i in range(e2.node_minus.n_edges):
                    self.add_inner_edge(e2.node_minus.edge_list[i], e2.node_minus)

            else:
                # tree grows along cycle

                while e2.node_minus.pair != blossom.pair:
                    e = e2
                    e2 = e.node_minus.pair

                    if e2.node_plus == e.node_minus:
                        swap_nodes(e2)
                    e2.parent = e
                    for i in range(e2.node_minus.n_edges):
                        self.add_inner_edge(e2.node_minus.edge_list[i], e2.node_minus)

                    e = e2
                    e2 = e.cycle
                    if e2.node_minus == e.node_plus:
                        swap_nodes(e2)
                    e2.parent = e
                    for i in range(e2.node_plus.n_edges):
                        self.add_outer_edge(e2.node_plus.edge_list[i], e2.node_plus)

                for i in range(e2.node_minus.n_edges):
                    self.add_inner_edge(e2.node_minus.edge_list[i], e2.node_minus)

                blossom.pair.parent = e2

        # delete cycle information
        start = blossom.cycle_start
        e = start.cycle
        while e != start:
            e2 = e.cycle
            e.cycle = NULL
            e = e2
        e.cycle = NULL

    def expand_no_tree(self, blossom_index):
        cdef node *blossom
        cdef edge *pair
        cdef edge *e
        cdef edge *start
        cdef edge *e2


        assert self.len_nodes > blossom_index

        blossom = &self.nodes[blossom_index]

        assert blossom.restore_list != NULL


        if blossom.pair.node_plus == blossom:
            swap_nodes(blossom.pair)


        # restore graph structure
        for i in range(blossom.n_edges):
            e = blossom.edge_list[i]
            if e.node_plus == blossom:
                e.node_plus = blossom.restore_list[i]
            else:
                e.node_minus = blossom.restore_list[i]

        # re-pair blossom if necessary
        if blossom.pair.node_minus.pair != <edge*> -1:
            start = blossom.pair.node_minus.pair.cycle


            if start.node_plus == blossom.pair.node_minus:
                start = start.cycle
            if start.node_minus == blossom.pair.node_minus:
                start = start.cycle


            e = start

            while e.cycle != start:
                self._pair_edge(e)
                e = e.cycle.cycle

        blossom.pair.node_minus.pair = blossom.pair


        # delete cycle information
        start = blossom.cycle_start
        e = start.cycle
        while e != start:
            e2 = e.cycle
            e.cycle = NULL
            e = e2
        e.cycle = NULL

    def do_edge(self, edge_index):
        cdef edge* e
        assert edge_index < self.len_edges
        e = &self.edges[edge_index]

        if e.parent:
            return "already in tree"
        if e.cycle != NULL:
            return "in cycle"
        if e.node_plus.pair == NULL or e.node_plus.pair.parent == NULL:
            return "not outer"

        if e.node_minus.pair == NULL:
            self.augment(edge_index)
            self.set_root()
            return "augment"
        if e.node_minus.pair.parent == NULL:
            self.grow(edge_index)
            return "grow"
        if e.node_minus.pair.parent != NULL:
            if e.node_minus.pair.node_plus == e.node_minus:
                self.shrink(edge_index)
                return "shrink"
            else:
                return "ignore"

    def pair_all(self, upto=1000000):
        assert self.root.node_plus == NULL

        step = 0

        self.set_root()

        self.show()
        ip = 0
        while ip < self.len_instructions and step < upto:

            # try:
                # self.check_all()
            # except AssertionError, e:
                # self.show()
                # raise e
            r = ""
            if self.instructions[ip].edge.tag == self.instructions[ip].tag:
                print("step", step,"edge", self.instructions[ip].edge.index)
                r = self.do_edge(self.instructions[ip].edge.index)
                print(r)
                step +=1
            ip += 1
            if r == "augment":
                ip = 0

    def get_edge(self, edge_index):
        cdef edge *e
        e = &self.edges[edge_index]
        r = {
                "index": e.index,
                "slack": e.slack,
                "node_plus": e.node_plus.index,
                "node_minus": e.node_minus.index,
                }
        if e.parent != NULL:
            r["parent"] = e.parent.index
        else:
            r["parent"] = None

        return r

    def get_node(self, node_index):
        cdef node *n
        cdef int i
        n = &self.nodes[node_index]
        r = {
                "index": n.index,
                "y": n.y,
                }

        edge_list = []
        for i in range(n.n_edges):
            edge_list.append(n.edge_list[i].index)

        r["edge_list"] = edge_list

        if n.pair != NULL:
            r["pair"] = n.pair.index
        else:
            r["pair"] = None

        return r

    def get_root(self):
        if self.root.node_plus != NULL:
            return self.root.node_plus.index
        else :
            return -1 

    def raw_set_root(self, root_node_index):
        assert self.root.node_plus == NULL
        assert root_node_index < self.len_nodes
        self.root.node_plus = &self.nodes[root_node_index]
        self.nodes[root_node_index].pair = &self.root

        for i in range(self.root.node_plus.n_edges):
            self.add_outer_edge(self.root.node_plus.edge_list[i], self.root.node_plus)

    def set_root(self):
        cdef node *n

        assert self.root.node_plus == NULL

        for i in range(self.len_nodes):
            if self.nodes[i].pair == NULL:
                n = &self.nodes[i]
                break
        else:
            return -1

        self.root.node_plus = n
        n.pair = &self.root
        for i in range(n.n_edges):
            self.add_outer_edge(n.edge_list[i], n)

        return n.index

    def get_instructions(self):
        instructions = []
        for i in range(self.len_instructions):
            instructions.append(self.instructions[i].edge.index)

        return instructions

    def raw_set_parent(self, parent_index, child_index):

        cdef edge *p
        cdef edge *e

        p = &self.edges[parent_index]
        e = &self.edges[child_index]

        e.parent = p

    cdef void _pair_edge(self, edge* edge):
        edge.node_plus.pair = edge
        edge.node_minus.pair = edge

    def pair_edge(self, edge_index, pair=True):
        cdef edge *e
        e = &self.edges[edge_index]
        self._pair_edge(e)

    def __dealloc__(self):
        free(self.nodes)
        free(self.edges)
        free(self.incidence)
        free(self.restore)
        free(self.instructions)
        free(self.pos_x)
        free(self.pos_y)
    
