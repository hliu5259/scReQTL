# Seurat1-2.R
# LAST UPDATED ON DEC.22 2020
# filter the Seurat datset based on the feature distribution(saved in the '_beforefilter.rds')

# load package
print('loading required packages: data.table, tidyverse, Seurat, SingleR')
suppressPackageStartupMessages(library(data.table))
suppressPackageStartupMessages(library(tidyverse))
suppressPackageStartupMessages(library(Seurat))
suppressPackageStartupMessages(library(SingleR))
suppressPackageStartupMessages(library(optparse))

option_list <- list(
  make_option(c("-s", "--samplelist"), action = "store", type ="character", 
              default = NULL, help= "4-columned file with columns (no headers): sample name, min_nfeature, max_nfeature, and max_mitochondrial_gene_percent")
)

opt <- parse_args(OptionParser(option_list=option_list, description = "-s option is necessary!!!!", usage = "usage: Rscript seurat1-2.R -s <sample_list>"))

if (packageVersion("Seurat") < "3.0.0") {
  stop(paste0("You have Seurat version", packageVersion("Seurat"), "installed. Please make sure you have Seurat version > 3.0.0"))
}


if (is.null(opt$samplelist)) stop("Not provided the required input. To view proper syntax type: Rscript seurat1-2.R -h")
#setup graph environment for Unix-based system
# options(bitmapType="cairo")

# input sample list, min feature, max feature, max percent of mitochondrial genes
sample_list <<- fread(opt$samplelist, header = F)
sample_id <<- sample_list$V1
nfeature_min <- as.numeric(sample_list$V2)
nfeature_max <- as.numeric(sample_list$V3)
n_percent <- as.numeric(sample_list$V4)

# check the argument
if (nrow(sample_list) == 0) stop("No sample names found!")
if (ncol(sample_list) < 4) stop("Fewer feature arguments supplied than expected!")

# check the import dataset
for (i in 1:nrow(sample_list)){
  if (file.exists(paste0(sample_id[i], "_beforefilter.rds") == F))
    print(paste0(sample_id[i], "_beforefilter.rds NOT exist"))
  else print(paste0("gonna process ", sample_id[i]))
}



for (i in 1:nrow(sample_list)){
    # read Seurat dataset
    Gene_Seurat <- readRDS(paste0(sample_id[i],"_beforefilter.rds"))
    # write outputs
    if (!dir.exists(sample_id[i])) {
      cat('Creating output directory...\n')
      dir.create(sample_id[i], showWarnings = FALSE)
    }
      
    # filter unique feature
    Gene_Seurat <- subset(x = Gene_Seurat, subset = nFeature_RNA >nfeature_min[i] & nFeature_RNA <nfeature_max[i] & percent.mt <n_percent[i] )
    
    # plot filtered feature distribution
    png(paste0(sample_id[i],"_feature_distribution_filtered.png"), width = 850, height = 400)
    plot1 <- FeatureScatter(object = Gene_Seurat, feature1 = "nCount_RNA", feature2 = "percent.mt") +
      geom_point()+ scale_fill_viridis_c() + stat_density_2d(aes(fill = stat(nlevel)), geom = "polygon") +
      geom_hex(bins = 70)  + theme_bw()
    plot2 <- FeatureScatter(object = Gene_Seurat, feature1 = "nCount_RNA", feature2 = "nFeature_RNA")+
      geom_point() + stat_density_2d(aes(fill = stat(nlevel)), geom = "polygon") +scale_fill_viridis_c() +
      geom_hex(bins = 70)  + theme_bw()
    print(plot1 + plot2)
    dev.off()
    
    # save filterd Seurat rds file
    saveRDS(Gene_Seurat,paste0(sample_id[i],"_filtered.rds"))
    
    # remove rds file produced before filtering
    file.remove(paste0(sample_id[i]), "_beforefilter.rds")
    
    # normatlization and scale
    Gene_Seurat <- SCTransform(object = Gene_Seurat, vars.to.regress = "percent.mt", verbose = FALSE, variable.features.n = 6000)
    nor_gene_matrix <- as.data.frame(Gene_Seurat@assays[["RNA"]]@data)
    
    # build the normatlized gene expression mattrix
    fwrite(nor_gene_matrix, paste0(sample_id[i],"_GE_matrix_filtered.txt"), sep = '\t', quote = F, row.names = T)

    # PCA and cluster
    Gene_Seurat <- RunPCA(Gene_Seurat, verbose = FALSE, npcs = 20)
    
    # plot pca distribution
    png(paste0(sample_id[i],"_Seurat_pca.png"), width = 450, height = 400)
    print(ElbowPlot(object = Gene_Seurat))
    dev.off()
    
    # use UMAP as visualization method
    Gene_Seurat<- RunUMAP(Gene_Seurat, dims = 1:20)
    Gene_Seurat <- FindNeighbors(Gene_Seurat, verbose = FALSE, dims = 1:20)
    Gene_Seurat <- FindClusters(Gene_Seurat, verbose = FALSE, resolution = 0.2)

    png(paste0(sample_id[i],'_clusters_Seurat_umap.png'), width = 450, height = 400)
    print(DimPlot(Gene_Seurat, label = TRUE, reduction = "umap", group.by ="seurat_clusters") + NoLegend())
    dev.off()
    
    # build up Seurat cluster
    ide <- data.frame(Gene_Seurat@active.ident)
    fwrite(ide, paste0(sample_id[i],'_clusters_Seurat.txt'),sep = "\t",quote = F, row.names = T, col.names = T)

    # use SingleR to annotate cell types
    # set up blueprintEncodeData as reference datset
    rna_re <- BlueprintEncodeData()
    b <- GetAssayData(Gene_Seurat)
    
    # get cluster information from Seurat
    cluster <- Gene_Seurat@active.ident
    
    # link Seurat clusters to SinlgR clusters
    result_cluster <- SingleR(test = b, ref = rna_re, labels = rna_re$label.fine, method="cluster", clusters = cluster)
    Gene_Seurat[["SingleR.cluster.labels"]] <-
      result_cluster$labels[match(Gene_Seurat[[]]["seurat_clusters"]$seurat_clusters, rownames(result_cluster))]
    png(paste0(sample_id[i],"_beforebatchcc_SingleR.png"), width = 450, height = 300)
    print(DimPlot(Gene_Seurat, group.by =  "SingleR.cluster.labels", reduction = "umap", label = TRUE) + labs(title = sample_id[i]))
    dev.off()
    # plot heatmap
    png(paste0(sample_id[i],"_filtered_heatmap.png"), width = 450, height = 300)
    print(plotScoreHeatmap(result_cluster))
    dev.off()
    
    # save Seurat clustered sinleR annotated rds file
    saveRDS(Gene_Seurat, file = paste0(sample_id[i],"_Seurat_clustered_singleR.rds"))


}
