import argparse
import math


# calculates distance between pointA(x,y) and pointB(X,Y)
def min_distance(x,y,X,Y):
	return round(math.sqrt((x - X)**2 + (y - Y)**2),1)

# returns the list of node's neighbours
def find_neighbours(root, nodes, tree, diam, cov):

	if len(nodes) == 0:
		return

	index = len(tree)
	for child in range(diam**2):
		if child in nodes and min_distance(root/diam, root%diam, child/diam, child%diam) <= cov:
			tree.append((child,root))
			nodes.remove(child)
	

	for k in [x[0] for x in tree[index:]]:
		find_neighbours(k, nodes, tree, diam, cov)

	return
	
	
def Main():

	parser = argparse.ArgumentParser(usage='python topo.py D C')
	parser.add_argument('size', type=int, help='an integer for grid size')
	parser.add_argument('coverage', type=float, help='a float for coverage distance')
	parser.add_argument('node',type=int)                
	args = parser.parse_args()

	root = args.node

	nodes = []
	for i in range(args.size**2):
		nodes.append(i)

	tree = []
	find_neighbours(root, nodes, tree, args.size, args.coverage)
	
	f = open("topology3.txt","w")
	for i in tree:
		f.write(str(i[0])+" "+str(i[1])+" -50\r\n")
		f.write(str(i[1])+" "+str(i[0])+" -50\r\n")

	f.close()
if __name__ == "__main__":
	Main()