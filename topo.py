import argparse
import math



# calculates distance between pointA(x,y) and pointB(X,Y)
def min_distance(x,y,X,Y):
	return round(math.sqrt((x - X)**2 + (y - Y)**2),1)

# returns the list of node's neighbours
def find_neighbours(node, diam, cov):

	for i in range(diam*diam):
		print(i),#str(i/diam)+str(i%diam)),
		if i%diam == diam-1: 
			print(" ")

	neighbours = []
	for i in range(diam):
		for j in range(diam):
			if min_distance(node/diam,node%diam,i,j) <= cov:
				neighbours.append((i*diam)+j)

	#print("Node "+str(node)+" has "+str(count)+" neighbours")
	print(neighbours)
def Main():

	parser = argparse.ArgumentParser(usage='python topo.py D C')
	parser.add_argument('size', type=int, help='an integer for grid size')
	parser.add_argument('coverage', type=float, help='a float for coverage distance')
	parser.add_argument('node',type=int)                
	args = parser.parse_args()

	N = (args.node/10)*args.size+args.node%10

	find_neighbours(N,args.size,args.coverage)

if __name__ == "__main__":
	Main()